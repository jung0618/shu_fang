import 'dart:async';
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
import 'package:shufang_flutter/services/writing_candidate.dart';
import 'package:shufang_flutter/store/companion_store.dart';
import 'package:shufang_flutter/store/editor_store.dart';
import 'package:shufang_flutter/store/local_data_source.dart';
import 'package:shufang_flutter/store/local_prefs.dart';
import 'package:shufang_flutter/widgets/ai_chat_panel.dart';
import 'package:shufang_flutter/widgets/ai_actions.dart';
import 'package:shufang_flutter/widgets/writing_candidate_preview.dart';
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

  for (final scenario in [
    'rewrite',
    'append',
    'no-selection',
    'summary',
    'incomplete',
    'edit-revert',
    'ime',
    'chapter',
    'workspace',
    'direction',
    'edit-during',
  ]) {
    testWidgets('current chat comparison: $scenario', (tester) async {
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          const response = '他将杯子推近，等她先开口。';
          var calls = 0;
          final finish = Completer<void>();
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            await request.drain<void>();
            calls++;
            request.response.headers.contentType = ContentType(
              'text',
              'event-stream',
              charset: 'utf-8',
            );
            request.response.write(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': response},
                    'finish_reason': null,
                  },
                ],
              })}\n\n',
            );
            if (scenario == 'edit-during') {
              await request.response.flush();
              await finish.future;
            }
            if (scenario != 'incomplete') {
              request.response.write(
                'data: ${jsonEncode({
                  'choices': [
                    {'delta': <String, String>{}, 'finish_reason': 'stop'},
                  ],
                })}\n\n',
              );
              request.response.write('data: [DONE]\n\n');
            }
            await request.response.close();
          });
          final controller = TextEditingController(text: fixturePassage);
          if (scenario != 'no-selection') {
            controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: fixturePassage.length,
            );
          }
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
            final command =
                scenario == 'append'
                    ? '/续写'
                    : scenario == 'summary'
                    ? '/总结'
                    : '/改写';
            await tester.enterText(find.byType(TextField), command);
            await tester.tap(find.byTooltip('发送'));
            if (scenario == 'edit-during') {
              final deadline = DateTime.now().add(const Duration(seconds: 8));
              while (DateTime.now().isBefore(deadline) && calls == 0) {
                await Future<void>.delayed(const Duration(milliseconds: 20));
                await tester.pump(const Duration(milliseconds: 20));
              }
              expect(calls, 1);
              controller.text = '生成期间临时编辑';
              controller.text = fixturePassage;
              finish.complete();
            }
            if (scenario == 'incomplete') {
              final deadline = DateTime.now().add(const Duration(seconds: 8));
              while (DateTime.now().isBefore(deadline) &&
                  (ref.read(aiMessagesProvider).isEmpty ||
                      !ref
                          .read(aiMessagesProvider)
                          .last
                          .content
                          .contains('生成中断'))) {
                await Future<void>.delayed(const Duration(milliseconds: 20));
                await tester.pump(const Duration(milliseconds: 20));
              }
              expect(
                ref.read(aiMessagesProvider).last.content,
                contains('生成中断'),
              );
            } else {
              await waitForReply(tester, ref, 2);
            }
            expect(calls, 1);
            final eligible =
                !['no-selection', 'summary', 'incomplete'].contains(scenario);
            expect(find.text('只读比较'), eligible ? findsOneWidget : findsNothing);
            if (eligible) {
              if (scenario == 'direction') {
                await WritingGoalStore.save(
                  root: root.path,
                  book: '测试作品',
                  expectedVersion: null,
                  target: '以新的克制方向重新比较',
                  keep: '',
                  avoid: '',
                );
              }
              await tester.tap(find.text('只读比较'));
              final deadline = DateTime.now().add(const Duration(seconds: 8));
              while (DateTime.now().isBefore(deadline) &&
                  find.text('候选变化段').evaluate().isEmpty &&
                  find.textContaining('已变化；').evaluate().isEmpty) {
                await Future<void>.delayed(const Duration(milliseconds: 20));
                await tester.pump(const Duration(milliseconds: 20));
              }
              expect(find.byType(WritingCandidatePreview), findsOneWidget);
              expect(
                find.text('候选变化段'),
                ['direction', 'edit-during'].contains(scenario)
                    ? findsNothing
                    : findsOneWidget,
              );
              expect(controller.text, fixturePassage);
              if (scenario == 'rewrite') {
                final candidate =
                    tester
                        .widget<WritingCandidatePreview>(
                          find.byType(WritingCandidatePreview),
                        )
                        .candidate;
                final plan = await buildSlashContext(
                  ref,
                  candidate.source,
                  const SlashCommand(AiAction.rewrite, ''),
                );
                expect(
                  candidate.baseSha256,
                  WritingCandidate.fingerprint(fixturePassage),
                );
                expect(candidate.id, contains(candidate.completion.requestId));
                for (final change in <Map<String, dynamic>>[
                  {'output_sha256': '0' * 64},
                  {'context_sha256': '0' * 64},
                  {'source_id': 'another-draft'},
                  {'book': '其他作品'},
                  {'chapter': '其他章节'},
                  {'workspace_root': '${root.path}-other'},
                  {'task': 'summary'},
                  {'output_units': 1},
                ]) {
                  final completion = WritingRequestCompletion.fromJson({
                    ...candidate.completion.toJson(),
                    ...change,
                  });
                  expect(
                    () => WritingCandidate.fromCompleted(
                      source: candidate.source,
                      plan: plan,
                      completion: completion,
                      body: response,
                    ),
                    throwsStateError,
                  );
                }
              }
              if (scenario == 'append') {
                expect(find.textContaining('章节末尾插入'), findsOneWidget);
              }
              if (scenario == 'edit-revert') {
                controller.text = '测试中临时编辑';
                controller.text = fixturePassage;
              } else if (scenario == 'ime') {
                controller.value = controller.value.copyWith(
                  composing: const TextRange(start: 0, end: 1),
                );
                controller.clearComposing();
              } else if (scenario == 'chapter') {
                ref.read(currentChapterProvider.notifier).state = '第二章';
                ref.read(currentChapterProvider.notifier).state = '第一章';
              } else if (scenario == 'workspace') {
                localDataSource.selectWorkspace(root.path, isPrimary: false);
              }
              await tester.pumpAndSettle();
              if ([
                'edit-revert',
                'ime',
                'chapter',
                'workspace',
              ].contains(scenario)) {
                expect(find.text('候选变化段'), findsNothing);
              }
              await tester.tap(find.text('关闭'));
              await tester.pumpAndSettle();
              expect(controller.text, fixturePassage);
            }
            expect(calls, 1);
            expect(ref.read(pendingInsertProvider), isNull);
            expect(tester.takeException(), isNull);
          } finally {
            if (!finish.isCompleted) finish.complete();
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
            await server.close(force: true);
          }
        }, _LoopbackHttpOverrides()),
      );
    });
  }

  test('comparison keeps scalar boundaries and reconstructs both inputs', () {
    for (final pair in [
      ('甲😀乙', '甲😁乙'),
      ('𠀀雨', '𠀁雨'),
      ('abc', 'abc'),
      ('', '新增'),
      ('甲改乙改丙', '甲换乙换丙'),
      ('正文', ''),
    ]) {
      final diff = CandidateDifference.between(pair.$1, pair.$2);
      expect('${diff.prefix}${diff.removed}${diff.suffix}', pair.$1);
      expect('${diff.prefix}${diff.added}${diff.suffix}', pair.$2);
      expect(diff.prefix.runes.contains(0xfffd), isFalse);
      expect(diff.removed.runes.contains(0xfffd), isFalse);
      expect(diff.added.runes.contains(0xfffd), isFalse);
    }
    expect(CandidateDifference.between('甲😀乙', '甲😁乙').removed, '😀');
    expect(
      CandidateDifference.excerpt('${'甲' * 3999}😀尾'),
      startsWith('${'甲' * 3999}\n…'),
    );
  });
}
