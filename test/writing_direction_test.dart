import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/chapter_save_queue.dart';
import 'package:shufang_flutter/services/editor_context_capture.dart';
import 'package:shufang_flutter/services/writing_context.dart';
import 'package:shufang_flutter/services/writing_direction.dart';
import 'package:shufang_flutter/services/writing_goal.dart';
import 'package:shufang_flutter/services/writing_preferences.dart';
import 'package:shufang_flutter/services/writing_request_ledger.dart';
import 'package:shufang_flutter/store/editor_store.dart';
import 'package:shufang_flutter/store/local_data_source.dart';
import 'package:shufang_flutter/widgets/ai_actions.dart';

import 'support/practice_fixture.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('shufang-direction-');
    localDataSource.selectWorkspace(root.path, isPrimary: false);
  });
  tearDown(() async {
    localDataSource.clearUser();
    await root.delete(recursive: true);
  });

  Future<AuthorWritingGoal> saveGoal({int? version, bool enabled = true}) =>
      WritingGoalStore.save(
        root: root.path,
        book: '测试作品',
        expectedVersion: version,
        target: '让动作承担情绪。',
        keep: '保留简短的停顿。',
        avoid: '避免解释人物情绪。',
        enabled: enabled,
      );

  Future<WritingPreferences> confirm() async {
    await writePracticeFixture(root.path);
    return WritingPreferenceStore.confirm(
      root: root.path,
      book: '测试作品',
      expectedVersion: 0,
      sourceCaseId: 'practice-100',
      text: '争执中保留人物的沉默',
    );
  }

  WritingContextPlan plan(
    WritingDirectionSnapshot direction, {
    int budget = 4000,
    List<Map<String, String>> history = const [],
  }) => WritingContextBuilder.build(
    request: '请结合原句给一条建议。',
    manuscript: List.filled(3000, '他放下杯子。𠀀\n').join(),
    budget: budget,
    task: WritingTask.feedback,
    book: '测试作品',
    chapter: '第一章',
    sourceId: 'draft-fixture',
    direction: direction,
    history: history,
  );

  Future<WidgetRef> mountEditor(
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
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              editorRef = ref;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return editorRef;
  }

  test('missing choices remain empty and workspace paths stay local', () async {
    final direction = await WritingDirectionSnapshot.load(
      root: root.path,
      book: '测试作品',
    );
    final data = jsonDecode(direction.requestData);
    expect(data['author_goal']['enabled'], isFalse);
    expect(data['confirmed_preferences']['items'], isEmpty);
    expect(direction.requestData, isNot(contains(root.path)));
    final other = WritingDirectionSnapshot(
      root: '${root.path}/other',
      book: '测试作品',
      goal: null,
      preferences: WritingPreferences.empty('测试作品'),
    );
    expect(other.historyKey, isNot(direction.historyKey));
  });

  test(
    'direction is budgeted user data after history, never system text',
    () async {
      await saveGoal();
      await confirm();
      final direction = await WritingDirectionSnapshot.load(
        root: root.path,
        book: '测试作品',
      );
      final prepared = plan(
        direction,
        history: [
          {'role': 'user', 'content': '请看这一句'},
          {'role': 'assistant', 'content': '模型观察不是偏好'},
        ],
      );
      expect(prepared.usedUnits, lessThanOrEqualTo(4000));
      expect(prepared.partial, isTrue);
      expect(prepared.messages.first['content'], isNot(contains('让动作承担情绪。')));
      expect(prepared.messages[prepared.messages.length - 2], {
        'role': 'user',
        'content': direction.requestData,
      });
      final data = jsonDecode(
        prepared.messages[prepared.messages.length - 2]['content']!,
      );
      expect(data['author_goal']['origin'], 'author_explicit');
      expect(data['confirmed_preferences']['items'], hasLength(1));
      expect(direction.requestData, isNot(contains(fixturePassage)));
      expect(direction.requestData, isNot(contains('动作带着迟疑')));
      expect(prepared.directionKey, direction.historyKey);
      expect(prepared.description, contains('1 项确认偏好'));
    },
  );

  test(
    'revocation and disabled goal remove old text from all new requests',
    () async {
      final goal = await saveGoal();
      final preferences = await confirm();
      final before = await WritingDirectionSnapshot.load(
        root: root.path,
        book: '测试作品',
      );
      final frozen = before.requestData;
      await WritingPreferenceStore.revoke(
        root: root.path,
        book: '测试作品',
        expectedVersion: preferences.version,
        id: preferences.active.single.id,
      );
      await saveGoal(version: goal.version, enabled: false);
      final after = await WritingDirectionSnapshot.load(
        root: root.path,
        book: '测试作品',
      );
      expect(after.historyKey, isNot(before.historyKey));
      expect(before.requestData, frozen);
      final history = ChatMessage.recentContext([
        ChatMessage(
          role: 'user',
          content: '争执中保留人物的沉默',
          directionKey: before.historyKey,
        ),
        ChatMessage(
          role: 'assistant',
          content: '让动作承担情绪。',
          directionKey: before.historyKey,
        ),
      ], directionKey: after.historyKey);
      expect(history, isEmpty);
      final packet = jsonEncode(plan(after, history: history).toPacket());
      for (final old in ['争执中保留人物的沉默', '让动作承担情绪。', '保留简短的停顿。', '避免解释人物情绪。']) {
        expect(packet, isNot(contains(old)));
      }
      expect(
        (await WritingPreferenceStore.load(
          root.path,
          '测试作品',
        )).items.single.active,
        isFalse,
      );
      final restored = await saveGoal(version: goal.version + 1);
      final restoredDirection = await WritingDirectionSnapshot.load(
        root: root.path,
        book: '测试作品',
      );
      expect(restored.enabled, isTrue);
      expect(restoredDirection.historyKey, isNot(before.historyKey));
    },
  );

  test(
    'history keeps only the current contiguous segment and successful content',
    () {
      ChatMessage message(String text, String? key, {bool include = true}) =>
          ChatMessage(
            role: 'user',
            content: text,
            directionKey: key,
            includeInContext: include,
          );
      final history = ChatMessage.recentContext([
        message('旧相同方向', 'now'),
        message('方向曾更改', 'other'),
        message('本轮一', 'now'),
        message('失败回复', 'now', include: false),
        message('本轮二', 'now').copyWith(content: '更新后的本轮二'),
      ], directionKey: 'now');
      expect(history.map((m) => m['content']), ['本轮一', '更新后的本轮二']);
      expect(
        ChatMessage.recentContext([
          message('旧版无范围记录', null),
        ], directionKey: 'now'),
        isEmpty,
      );
    },
  );

  test(
    'mismatched book is rejected rather than borrowing its choices',
    () async {
      final goal = await saveGoal();
      expect(
        () => WritingDirectionSnapshot(
          root: root.path,
          book: '另一作品',
          goal: goal,
          preferences: WritingPreferences.empty('另一作品'),
        ),
        throwsArgumentError,
      );
      final other = WritingDirectionSnapshot(
        root: root.path,
        book: '另一作品',
        goal: null,
        preferences: WritingPreferences.empty('另一作品'),
      );
      expect(() => plan(other), throwsArgumentError);
    },
  );

  test(
    'escaped author choices are never trimmed to make a small budget fit',
    () async {
      final goal = await saveGoal();
      final preferences = WritingPreferences.fromJson({
        'schema_version': 1,
        'origin': 'author_confirmed',
        'book': '测试作品',
        'version': 1,
        'items': [
          for (var i = 1; i <= 8; i++)
            {
              'id': 'preference-$i',
              'text': List.filled(100, '"\n').join(),
              'source_case_id': 'practice-100',
              'confirmed_at': '2026-10-29T00:00:00Z',
              'revoked_at': null,
            },
        ],
      });
      final direction = WritingDirectionSnapshot(
        root: root.path,
        book: '测试作品',
        goal: goal,
        preferences: preferences,
      );
      expect(() => plan(direction), throwsStateError);
      final prepared = plan(direction, budget: 8000);
      expect(prepared.usedUnits, lessThanOrEqualTo(8000));
      expect(
        prepared.messages[prepared.messages.length - 2]['content'],
        direction.requestData,
      );
      expect(
        jsonDecode(direction.requestData)['confirmed_preferences']['items'],
        hasLength(8),
      );
      // UTF-16 slicing must also preserve supplementary characters in the prose.
      final encoded = jsonEncode(prepared.toPacket());
      expect(utf8.decode(utf8.encode(encoded)), encoded);
    },
  );

  test(
    'corrupt choices stop preparation and preserve the original file',
    () async {
      final file = File(
        WritingGoalStore.pathFor(root: root.path, book: '测试作品'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString('{broken');
      await expectLater(
        WritingDirectionSnapshot.load(root: root.path, book: '测试作品'),
        throwsFormatException,
      );
      expect(await file.readAsString(), '{broken');
      expect(await WritingRequestLedger.directory(root.path).exists(), isFalse);
    },
  );

  testWidgets(
    'all shortcut tasks share fresh choices and a frozen manuscript',
    (tester) async {
      final controller = TextEditingController(text: '他把杯子放回桌上。');
      final editorRef = await mountEditor(tester, controller);
      final source = EditorSourceSnapshot.capture(editorRef);
      await tester.runAsync(() async {
        final goal = await saveGoal();
        await confirm();
        controller.text = '载入目标时已经改动的正文。';
        for (final task
            in {
              AiAction.continueWrite: WritingTask.continuation,
              AiAction.rewrite: WritingTask.revision,
              AiAction.suggest: WritingTask.feedback,
              AiAction.summary: WritingTask.summary,
            }.entries) {
          final prepared = await buildSlashContext(
            editorRef,
            source,
            SlashCommand(task.key, '保留原意'),
          );
          expect(prepared.task, task.value);
          expect(prepared.messages.last['content'], contains('保留原意'));
          final packet = jsonEncode(prepared.toPacket());
          expect(packet, contains('他把杯子放回桌上。'));
          expect(packet, isNot(contains('载入目标时已经改动的正文。')));
          expect(packet, contains('让动作承担情绪。'));
          expect(packet, contains('争执中保留人物的沉默'));
        }
        await saveGoal(version: goal.version, enabled: false);
        final next = await buildSlashContext(
          editorRef,
          source,
          const SlashCommand(AiAction.continueWrite, ''),
        );
        expect(jsonEncode(next.toPacket()), isNot(contains('让动作承担情绪。')));
      });
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('workspace switch during choice loading cancels preparation', (
    tester,
  ) async {
    final controller = TextEditingController(text: '原工作区的草稿。');
    final editorRef = await mountEditor(tester, controller);
    final source = EditorSourceSnapshot.capture(editorRef);
    await tester.runAsync(() async {
      final pending = source.loadDirection();
      final other = Directory('${root.path}/other');
      localDataSource.selectWorkspace(other.path, isPrimary: false);
      // Switching back must not revive the old editor session.
      localDataSource.selectWorkspace(root.path, isPrimary: false);
      await expectLater(pending, throwsStateError);
      final foreign = WritingDirectionSnapshot(
        root: other.path,
        book: '测试作品',
        goal: null,
        preferences: WritingPreferences.empty('测试作品'),
      );
      expect(
        () => source.plan(request: '建议', budget: 4000, direction: foreign),
        throwsArgumentError,
      );
    });
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'corrupt preferences block shortcut before any transport or ledger',
    (tester) async {
      final controller = TextEditingController(text: '他没有说话。');
      final editorRef = await mountEditor(tester, controller);
      await tester.runAsync(() async {
        await saveGoal();
        final file = File(WritingPreferenceStore.pathFor(root.path, '测试作品'));
        await file.writeAsString('{invalid');
        final errors = <String>[];
        await dispatchSlashCommandToChat(
          editorRef,
          const SlashCommand(AiAction.continueWrite, ''),
          onUpdate: (_, __) => fail('No model request should run'),
          onError: errors.add,
        );
        expect(errors, hasLength(1));
        expect(
          await WritingRequestLedger.directory(root.path).exists(),
          isFalse,
        );
        expect(await file.readAsString(), '{invalid');
      });
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
