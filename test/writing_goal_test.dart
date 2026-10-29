import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/chapter_save_queue.dart';
import 'package:shufang_flutter/services/editor_context_capture.dart';
import 'package:shufang_flutter/services/writing_goal.dart';
import 'package:shufang_flutter/services/writing_practice.dart';
import 'package:shufang_flutter/services/writing_practice_history.dart';
import 'package:shufang_flutter/services/writing_preferences.dart';
import 'package:shufang_flutter/store/editor_store.dart';
import 'package:shufang_flutter/store/local_data_source.dart';

import 'support/practice_fixture.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shufang-goal-');
  });
  tearDown(() async {
    localDataSource.clearUser();
    await directory.delete(recursive: true);
  });

  Future<AuthorWritingGoal> save({
    String book = '测试作品',
    int? expectedVersion,
    String target = '对白克制，把情绪留在动作里。',
    String keep = '保留简短、偶尔生硬的停顿。',
    String avoid = '避免直接解释人物情绪。',
    bool enabled = true,
  }) => WritingGoalStore.save(
    root: directory.path,
    book: book,
    expectedVersion: expectedVersion,
    target: target,
    keep: keep,
    avoid: avoid,
    enabled: enabled,
  );

  test(
    'explicit goal persists, stays scoped, and keeps one recovery version',
    () async {
      expect(
        await WritingGoalStore.load(root: directory.path, book: '测试作品'),
        isNull,
      );
      final first = await save(target: '  写出有留白的对白。  ');
      expect(first.target, '写出有留白的对白。');
      final second = await save(
        expectedVersion: first.version,
        target: '让动作承担情绪。',
      );
      final loaded = await WritingGoalStore.load(
        root: directory.path,
        book: '测试作品',
      );
      expect(loaded!.toJson(), second.toJson());
      expect(loaded.version, 2);
      expect(first.target, '写出有留白的对白。');
      final path = WritingGoalStore.pathFor(root: directory.path, book: '测试作品');
      final backup = File(
        '${File(path).parent.path}/.recovery/.writing-goal.json.previous',
      );
      expect(jsonDecode(await backup.readAsString()), first.toJson());
      expect(
        await WritingGoalStore.load(root: directory.path, book: '另一作品'),
        isNull,
      );
      expect(
        await WritingGoalStore.load(
          root: '${directory.path}/other',
          book: '测试作品',
        ),
        isNull,
      );
    },
  );

  test(
    'simultaneous stale editors cannot silently overwrite one another',
    () async {
      final first = await save();
      final results = await Future.wait([
        save(
          expectedVersion: first.version,
          target: '先保存的作者选择。',
        ).then<Object>((value) => value, onError: (Object error) => error),
        save(
          expectedVersion: first.version,
          target: '过期编辑。',
        ).then<Object>((value) => value, onError: (Object error) => error),
      ]);
      expect(results.whereType<AuthorWritingGoal>(), hasLength(1));
      expect(results.whereType<StateError>(), hasLength(1));
      final latest = await WritingGoalStore.load(
        root: directory.path,
        book: '测试作品',
      );
      expect(latest!.version, 2);
      expect(latest.target, '先保存的作者选择。');
      // A rejected operation does not poison later writes.
      expect((await save(expectedVersion: latest.version)).version, 3);
    },
  );

  test(
    'disabled goal retains local text but excludes it from new requests',
    () async {
      final first = await save();
      final disabled = await save(
        expectedVersion: first.version,
        enabled: false,
      );
      expect(disabled.target, first.target);
      expect(disabled.requestData, isNot(contains(first.target)));
      expect(jsonDecode(disabled.requestData), {
        'kind': 'author_writing_goal',
        'enabled': false,
      });
      final restored = await save(expectedVersion: disabled.version);
      expect(restored.enabled, isTrue);
      expect(restored.version, 3);
    },
  );

  test('malformed goal blocks overwrite and preserves bytes', () async {
    final path = WritingGoalStore.pathFor(root: directory.path, book: '测试作品');
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('{broken');
    await expectLater(
      WritingGoalStore.load(root: directory.path, book: '测试作品'),
      throwsFormatException,
    );
    await expectLater(save(), throwsFormatException);
    expect(await file.readAsString(), '{broken');
  });

  test(
    'wrong scope, future schema and nonauthor records are rejected',
    () async {
      final first = await save();
      for (final change in <Map<String, Object>>[
        {'book': '另一作品'},
        {'schema_version': 99},
        {'origin': 'model_observation'},
        {'version': 0},
        {'enabled': 'yes'},
        {'updated_at': 'yesterday'},
      ]) {
        final file = File(
          WritingGoalStore.pathFor(root: directory.path, book: '测试作品'),
        );
        await file.writeAsString(jsonEncode({...first.toJson(), ...change}));
        await expectLater(
          WritingGoalStore.load(root: directory.path, book: '测试作品'),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'path traversal and oversized or empty fields fail without writing',
    () async {
      for (final book in ['..', '../other', r'bad\name', 'CON', '']) {
        expect(
          () => WritingGoalStore.pathFor(root: directory.path, book: book),
          throwsArgumentError,
        );
      }
      await expectLater(save(target: '  '), throwsFormatException);
      await expectLater(
        save(keep: List.filled(301, '字').join()),
        throwsFormatException,
      );
      expect(
        await WritingGoalStore.load(root: directory.path, book: '测试作品'),
        isNull,
      );
    },
  );

  test(
    'goal and keep/avoid are budgeted request data; old snapshots remain frozen',
    () async {
      final first = await save();
      final second = await save(
        expectedVersion: first.version,
        target: '改为热闹、有戏剧感的对白。',
      );
      final passage = List.filled(15, '他端起杯子，又放下了。').join();
      for (final budget in [4000, 8000, 16000]) {
        final plan = WritingPracticeContext.build(
          passage: passage,
          goal: PracticeGoal.dialogue,
          intention: '让读者感到犹豫。',
          book: '测试作品',
          chapter: '第一章',
          sourceId: 'source-1',
          budget: budget,
          authorGoal: first,
          revision: '“算了。”他把杯子推回桌子中间。',
        );
        expect(plan.usedUnits, lessThanOrEqualTo(budget));
        expect(plan.partial, isFalse);
        final request = plan.messages.last['content']!;
        expect(request, contains(first.target));
        expect(request, contains(first.keep));
        expect(request, contains(first.avoid));
        expect(request, isNot(contains(second.target)));
        expect(plan.messages.first['content'], isNot(contains(first.target)));
        expect(request, contains('original_for_comparison_only'));
      }
      expect(
        () => WritingPracticeContext.build(
          passage: passage,
          goal: PracticeGoal.dialogue,
          intention: '',
          book: '其他作品',
          chapter: '第一章',
          sourceId: 'source-1',
          budget: 8000,
          authorGoal: first,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'disabled and absent goals work without hidden old instructions',
    () async {
      final first = await save(enabled: false);
      for (final goal in [first, null]) {
        final plan = WritingPracticeContext.build(
          passage: '他站在门边，看了一眼，又退了回去。',
          goal: PracticeGoal.scene,
          intention: '让读者感到迟疑。',
          book: '测试作品',
          chapter: '第一章',
          sourceId: 'source-1',
          budget: 4000,
          authorGoal: goal,
        );
        expect(plan.messages.last['content'], isNot(contains(first.target)));
      }
    },
  );

  test(
    'too much context fails instead of silently truncating the exercise',
    () async {
      final goal = await save(target: List.filled(350, '“').join());
      expect(
        () => WritingPracticeContext.build(
          passage: List.filled(1800, '字').join(),
          revision: List.filled(1800, '句').join(),
          goal: PracticeGoal.dialogue,
          intention: List.filled(400, '意').join(),
          book: '测试作品',
          chapter: '第一章',
          sourceId: 'source-1',
          budget: 4000,
          authorGoal: goal,
        ),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'saved case freezes reviewed goal and preferences after update and revocation',
    (tester) async {
      localDataSource.selectWorkspace(directory.path, isPrimary: false);
      final controller = TextEditingController(text: '“算了。”他把杯子推回桌子中间。');
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      late EditorSourceSnapshot source;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBookProvider.overrideWith((ref) => '测试作品'),
            currentChapterProvider.overrideWith((ref) => '第一章'),
            editorControllerProvider.overrideWith(
              (ref) => (
                address: ChapterAddress(
                  localDataSource.storageRoot,
                  '测试作品',
                  '第一章',
                ),
                controller: controller,
              ),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                source = EditorSourceSnapshot.capture(ref);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final first = await save();
        await writePracticeFixture(directory.path);
        final preferences = await WritingPreferenceStore.confirm(
          root: directory.path,
          book: '测试作品',
          expectedVersion: 0,
          sourceCaseId: 'practice-100',
          text: '争执中保留人物的沉默',
        );
        final snapshot = preferences.snapshot;
        await WritingPreferenceStore.revoke(
          root: directory.path,
          book: '测试作品',
          expectedVersion: preferences.version,
          id: preferences.active.single.id,
        );
        await save(expectedVersion: first.version, target: '之后改了的目标。');
        final path = await WritingPracticeStore.save(
          source: source,
          goal: PracticeGoal.dialogue,
          intention: '克制',
          passage: controller.text,
          feedback: PracticeFeedback.parse(
            '{"observations":[]}',
            controller.text,
          ),
          model: 'offline-fixture',
          revision: '自己改的版本',
          reflection: '',
          decision: 'try',
          authorGoal: first,
          preferences: snapshot,
        );
        final record = jsonDecode(await File(path).readAsString());
        expect(record['schema_version'], 3);
        expect(record['author_goal_snapshot'], first.toJson());
        expect(record['author_preferences_snapshot'], snapshot.toJson());
        final recalled = await WritingPracticeHistory.loadCase(
          source.root,
          source.book,
          record['id'] as String,
        );
        expect(recalled.authorGoal!.toJson(), first.toJson());
        expect(recalled.preferences!.active.single.text, '争执中保留人物的沉默');
        expect(
          (await WritingPreferenceStore.load(source.root, source.book)).active,
          isEmpty,
        );
        expect(record['promoted_to_preference'], isFalse);
        expect(record['evidence_status'], 'author_recorded_unassessed');
        expect(record['workspace_root'], source.root);
      });
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
