import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/api/api_client.dart';
import 'package:shufang_flutter/services/chapter_save_queue.dart';
import 'package:shufang_flutter/services/writing_goal.dart';
import 'package:shufang_flutter/services/writing_preferences.dart';
import 'package:shufang_flutter/services/writing_request_ledger.dart';
import 'package:shufang_flutter/store/companion_store.dart';
import 'package:shufang_flutter/store/editor_store.dart';
import 'package:shufang_flutter/store/local_data_source.dart';
import 'package:shufang_flutter/store/local_prefs.dart';
import 'package:shufang_flutter/widgets/ai_chat_panel.dart';
import 'package:shufang_flutter/widgets/pixel_companion.dart';

import 'support/practice_fixture.dart';

class _LoopbackHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (uri) {
          if (uri.host != '127.0.0.1') {
            throw StateError('This fixture only permits loopback HTTP');
          }
          return 'DIRECT';
        };
}

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('shufang-direction-chat-');
    localDataSource.selectWorkspace(root.path, isPrimary: false);
    apiClient.disconnect();
  });
  tearDown(() async {
    await PrefsController.update(UserPrefs.defaults);
    localDataSource.clearUser();
    await root.delete(recursive: true);
  });

  Future<WidgetRef> mountChat(
    WidgetTester tester,
    TextEditingController controller,
  ) async {
    late WidgetRef editorRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentBookProvider.overrideWith((ref) => '测试作品'),
          currentChapterProvider.overrideWith((ref) => '第一章'),
          editorControllerProvider.overrideWith(
            (ref) => (
              address: ChapterAddress(root.path, '测试作品', '第一章'),
              controller: controller,
            ),
          ),
          companionControllerProvider.overrideWith(
            (ref) =>
                PixelCompanionController()
                  ..setVisible(false)
                  ..setAnimationsEnabled(false),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                editorRef = ref;
                return const AiChatPanel();
              },
            ),
          ),
        ),
      ),
    );
    return editorRef;
  }

  Future<void> waitForReply(
    WidgetTester tester,
    WidgetRef ref,
    int messageCount,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final messages = ref.read(aiMessagesProvider);
      if (messages.length == messageCount && messages.last.includeInContext) {
        await tester.pumpAndSettle();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
    }
    fail(
      'Local fixture did not complete: ${ref.read(aiMessagesProvider).map((m) => m.content).join(" | ")}',
    );
  }

  testWidgets(
    'chat reloads revoked choices, retains visible history, and prevents double send',
    (tester) async {
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          await WritingGoalStore.save(
            root: root.path,
            book: '测试作品',
            expectedVersion: null,
            target: '让动作承担情绪。',
            keep: '',
            avoid: '',
          );
          await writePracticeFixture(root.path);
          final preferences = await WritingPreferenceStore.confirm(
            root: root.path,
            book: '测试作品',
            expectedVersion: 0,
            sourceCaseId: 'practice-100',
            text: '争执中保留人物的沉默',
          );
          final requests = <Map<String, dynamic>>[];
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            requests.add(
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>,
            );
            request.response.headers.contentType = ContentType(
              'text',
              'event-stream',
              charset: 'utf-8',
            );
            request.response.write(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': requests.length == 1 ? '旧回答：争执中保留人物的沉默' : '新方向回复'},
                    'finish_reason': null,
                  },
                ],
              })}\n\n',
            );
            request.response.write(
              'data: ${jsonEncode({
                'choices': [
                  {'delta': <String, String>{}, 'finish_reason': 'stop'},
                ],
              })}\n\n',
            );
            request.response.write('data: [DONE]\n\n');
            await request.response.close();
          });
          final controller = TextEditingController(text: fixturePassage);
          try {
            await PrefsController.update(
              UserPrefs(
                currentProvider: 'local-fixture',
                selectedModel: 'offline-fixture',
                apiProviders: {
                  'local-fixture': {
                    'api_key_plain': 'fake-key',
                    'base_url': 'http://127.0.0.1:${server.port}',
                    'default_model': 'offline-fixture',
                  },
                },
              ),
            );
            final ref = await mountChat(tester, controller);
            await tester.enterText(find.byType(TextField), '请看原句');
            await tester.tap(find.byTooltip('发送'));
            await tester.tap(find.byTooltip('发送'));
            await waitForReply(tester, ref, 2);
            expect(requests, hasLength(1));
            expect(jsonEncode(requests.first), contains('让动作承担情绪。'));
            expect(jsonEncode(requests.first), contains('争执中保留人物的沉默'));

            await WritingPreferenceStore.revoke(
              root: root.path,
              book: '测试作品',
              expectedVersion: preferences.version,
              id: preferences.active.single.id,
            );
            await tester.enterText(find.byType(TextField), '重新给建议');
            await tester.tap(find.byTooltip('发送'));
            await waitForReply(tester, ref, 4);
            expect(requests, hasLength(2));
            expect(jsonEncode(requests[1]), isNot(contains('争执中保留人物的沉默')));
            expect(ref.read(aiMessagesProvider).first.content, '请看原句');
            expect(ref.read(aiMessagesProvider)[1].content, contains('旧回答'));
            expect(find.textContaining('作者方向变更前的对话未发送'), findsOneWidget);

            await tester.enterText(find.byType(TextField), '再具体一点');
            await tester.tap(find.byTooltip('发送'));
            await waitForReply(tester, ref, 6);
            expect(requests, hasLength(3));
            expect(jsonEncode(requests[2]), contains('新方向回复'));
            expect(jsonEncode(requests[2]), isNot(contains('争执中保留人物的沉默')));
            final records = await WritingRequestLedger.read(root.path);
            expect(records.records, hasLength(3));
            expect(
              records.records.every((r) => r.state == 'completed'),
              isTrue,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
            await server.close(force: true);
          }
        }, _LoopbackHttpOverrides()),
      );
    },
  );

  testWidgets(
    'broken direction blocks chat without clearing the author input',
    (tester) async {
      await tester.runAsync(() async {
        final file = File(
          WritingGoalStore.pathFor(root: root.path, book: '测试作品'),
        );
        await file.parent.create(recursive: true);
        await file.writeAsString('{broken');
        final controller = TextEditingController(text: fixturePassage);
        final ref = await mountChat(tester, controller);
        await tester.enterText(find.byType(TextField), '保留这个尚未发送的要求');
        await tester.tap(find.byTooltip('发送'));
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.textContaining('未发送：').evaluate().isNotEmpty) break;
        }
        expect(find.textContaining('未发送：'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '保留这个尚未发送的要求',
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isTrue,
        );
        expect(ref.read(aiMessagesProvider), isEmpty);
        expect(
          await WritingRequestLedger.directory(root.path).exists(),
          isFalse,
        );
        expect(await file.readAsString(), '{broken');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
    },
  );
}
