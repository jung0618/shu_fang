import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/writing_practice.dart';
import 'package:shufang_flutter/services/writing_practice_history.dart';
import 'package:shufang_flutter/services/writing_preferences.dart';

import 'support/practice_fixture.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('shufang-history-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  Future<WritingPreferences> confirm({
    int version = 0,
    String text = '对话冲突时保留沉默',
    String id = 'practice-100',
  }) => WritingPreferenceStore.confirm(
    root: directory.path,
    book: '测试作品',
    expectedVersion: version,
    sourceCaseId: id,
    text: text,
  );

  test(
    'pages numeric IDs, reports broken cases, and reads legacy schemas',
    () async {
      await writePracticeFixture(directory.path, id: 'practice-9', schema: 1);
      await writePracticeFixture(directory.path, id: 'practice-10', schema: 2);
      final broken = await writePracticeFixture(
        directory.path,
        id: 'practice-11',
      );
      await broken.writeAsString('{broken');
      await writePracticeFixture(directory.path, id: 'practice-12');
      final first = await WritingPracticeHistory.loadPage(
        directory.path,
        '测试作品',
        pageSize: 2,
      );
      expect(first.records.single.id, 'practice-12');
      expect(first.problems.single, contains('practice-11'));
      expect(first.nextCursor, 'practice-11');
      final second = await WritingPracticeHistory.loadPage(
        directory.path,
        '测试作品',
        beforeId: first.nextCursor,
        pageSize: 2,
      );
      expect(second.records.map((item) => item.id), [
        'practice-10',
        'practice-9',
      ]);
      expect(second.nextCursor, isNull);
      expect(second.records.last.authorGoal, isNull);
      expect(await broken.readAsString(), '{broken');
    },
  );

  test(
    'wrong scope, unsupported version, and fabricated quotes are rejected',
    () async {
      for (final change in [
        {'book': '另一作品'},
        {'workspace_root': '${directory.path}/other'},
        {'id': 'practice-101'},
        {'schema_version': 99},
        {'source_end': 999},
        {
          'feedback': [
            {
              'quote': '不存在的原句',
              'observation': '观察',
              'reason': '依据',
              'direction': '方向',
              'exercise': '任务',
            },
          ],
        },
      ]) {
        await writePracticeFixture(directory.path, changes: change);
        await expectLater(
          WritingPracticeHistory.loadCase(
            directory.path,
            '测试作品',
            'practice-100',
          ),
          throwsFormatException,
        );
      }
      expect(
        () =>
            PracticePaths.casePath(directory.path, '../other', 'practice-100'),
        throwsArgumentError,
      );
      expect(
        () => PracticePaths.casePath(directory.path, '测试作品', '../outside'),
        throwsArgumentError,
      );
      expect(
        (await WritingPracticeHistory.loadPage(directory.path, '另一作品')).records,
        isEmpty,
      );
    },
  );

  test(
    'confirm and revoke are explicit, versioned, scoped and recoverable',
    () async {
      final file = await writePracticeFixture(directory.path);
      final original = await file.readAsString();
      expect(
        (await WritingPreferenceStore.load(directory.path, '测试作品')).active,
        isEmpty,
      );
      final first = await confirm(text: '  对话冲突时保留沉默  ');
      expect(first.active.single.text, '对话冲突时保留沉默');
      expect(first.active.single.sourceCaseId, 'practice-100');
      expect(
        (await WritingPreferenceStore.load(directory.path, '另一作品')).active,
        isEmpty,
      );
      final revoked = await WritingPreferenceStore.revoke(
        root: directory.path,
        book: '测试作品',
        expectedVersion: 1,
        id: first.active.single.id,
      );
      expect(revoked.version, 2);
      expect(revoked.active, isEmpty);
      expect(revoked.items.single.revokedAt, isNotNull);
      expect(first.active, hasLength(1));
      final path = WritingPreferenceStore.pathFor(directory.path, '测试作品');
      final backup =
          await File(
            '${File(path).parent.path}/.recovery/.writing-preferences.json.previous',
          ).readAsString();
      expect(jsonDecode(backup), first.toJson());
      expect(await file.readAsString(), original);
    },
  );

  test(
    'every readable case schema permits explicit confirmation and revocation',
    () async {
      var version = 0;
      for (final schema in [1, 2, 3, 4]) {
        final id = 'practice-${100 + schema}';
        final file = await writePracticeFixture(
          directory.path,
          id: id,
          schema: schema,
        );
        final original = await file.readAsBytes();
        final record = await WritingPracticeHistory.loadCase(
          directory.path,
          '测试作品',
          id,
        );
        final confirmed = await confirm(version: version, id: record.id);
        expect(confirmed.active.single.sourceCaseId, id);
        final revoked = await WritingPreferenceStore.revoke(
          root: directory.path,
          book: '测试作品',
          expectedVersion: confirmed.version,
          id: confirmed.active.single.id,
        );
        expect(revoked.active, isEmpty);
        expect(revoked.items.last.sourceCaseId, id);
        expect(await file.readAsBytes(), original);
        version = revoked.version;
      }
      expect(version, 8);
    },
  );

  test(
    'unsupported case schema cannot create a preference or rewrite its source',
    () async {
      final file = await writePracticeFixture(directory.path, schema: 99);
      final original = await file.readAsBytes();
      await expectLater(confirm(), throwsFormatException);
      expect(
        await File(
          WritingPreferenceStore.pathFor(directory.path, '测试作品'),
        ).exists(),
        isFalse,
      );
      expect(await file.readAsBytes(), original);
    },
  );

  test(
    'damaged case content cannot be accepted by its version label alone',
    () async {
      for (final change in <Map<String, dynamic>>[
        {'source_end': 999},
        {'chapter': '../outside'},
        {
          'feedback_source': {'request_id': 'invented'},
        },
        {
          'feedback': [
            {'quote': '不存在的引用'},
          ],
        },
      ]) {
        final file = await writePracticeFixture(
          directory.path,
          schema: 4,
          changes: change,
        );
        final original = await file.readAsBytes();
        await expectLater(confirm(), throwsFormatException);
        expect(
          await File(
            WritingPreferenceStore.pathFor(directory.path, '测试作品'),
          ).exists(),
          isFalse,
        );
        expect(await file.readAsBytes(), original);
      }
    },
  );

  test(
    'stale concurrent confirmation cannot overwrite and later updates recover',
    () async {
      await writePracticeFixture(directory.path);
      final results = await Future.wait([
        confirm(
          text: '保留口语',
        ).then<Object>((value) => value, onError: (Object error) => error),
        confirm(
          text: '保留短句',
        ).then<Object>((value) => value, onError: (Object error) => error),
      ]);
      expect(results.whereType<WritingPreferences>(), hasLength(1));
      expect(results.whereType<StateError>(), hasLength(1));
      expect((await confirm(version: 1, text: '场景转换时保留空间锚点')).version, 2);
    },
  );

  test(
    'bad preference files and missing or foreign source cannot be overwritten',
    () async {
      await writePracticeFixture(directory.path);
      final path = WritingPreferenceStore.pathFor(directory.path, '测试作品');
      final file = File(path);
      await file.writeAsString('{broken');
      await expectLater(confirm(), throwsFormatException);
      expect(await file.readAsString(), '{broken');
      await file.writeAsString(
        jsonEncode(WritingPreferences.empty('另一作品').toJson()),
      );
      await expectLater(confirm(), throwsFormatException);
      await file.writeAsString(
        jsonEncode(WritingPreferences.empty('测试作品').toJson()),
      );
      await expectLater(confirm(id: 'practice-999'), throwsFormatException);
      await writePracticeFixture(
        directory.path,
        changes: {'workspace_root': '${directory.path}/other'},
      );
      await expectLater(confirm(), throwsFormatException);
      expect((jsonDecode(await file.readAsString()) as Map)['version'], 0);
    },
  );

  test(
    'invalid and duplicate text and active capacity do not create preferences',
    () async {
      await writePracticeFixture(directory.path);
      await expectLater(confirm(text: ''), throwsFormatException);
      await expectLater(confirm(text: '字' * 201), throwsFormatException);
      var current = await confirm();
      await expectLater(confirm(version: 1), throwsStateError);
      for (var index = 1; index < 8; index++) {
        current = await confirm(version: current.version, text: '第$index项作者选择');
      }
      await expectLater(
        confirm(version: current.version, text: '超过容量'),
        throwsStateError,
      );
      expect(
        (await WritingPreferenceStore.load(directory.path, '测试作品')).active,
        hasLength(8),
      );
    },
  );

  test(
    'revocation affects new context, frozen snapshots retain provenance within budget',
    () async {
      await writePracticeFixture(directory.path);
      final current = await confirm();
      final snapshot = current.snapshot;
      final revoked = await WritingPreferenceStore.revoke(
        root: directory.path,
        book: '测试作品',
        expectedVersion: 1,
        id: current.active.single.id,
      );
      writingContextPlanForTest(preferences: snapshot);
      final plan = WritingPracticeContext.build(
        passage: fixturePassage,
        goal: PracticeGoal.dialogue,
        intention: '含蓄',
        book: '测试作品',
        chapter: '第一章',
        sourceId: 'draft-100',
        budget: 4000,
        preferences: revoked,
      );
      expect(
        plan.messages.map((item) => item['content']).join(),
        isNot(contains('对话冲突时保留沉默')),
      );
      expect(plan.usedUnits, lessThanOrEqualTo(4000));
      expect(snapshot.active.single.sourceCaseId, 'practice-100');
      expect(revoked.snapshot.items, isEmpty);
      expect(() => snapshot.items.clear(), throwsUnsupportedError);
      expect(
        () => WritingPracticeContext.build(
          passage: fixturePassage,
          goal: PracticeGoal.dialogue,
          intention: '',
          book: '其他',
          chapter: '第一章',
          sourceId: '',
          budget: 4000,
          preferences: snapshot,
        ),
        throwsArgumentError,
      );
    },
  );
}

// Check the same snapshot used by the original and revision request builders.
void writingContextPlanForTest({required WritingPreferences preferences}) {
  for (final revision in [null, '他把杯子放下，看向门口。']) {
    final plan = WritingPracticeContext.build(
      passage: fixturePassage,
      goal: PracticeGoal.dialogue,
      intention: '',
      book: '测试作品',
      chapter: '第一章',
      sourceId: 'draft-100',
      budget: 4000,
      preferences: preferences,
      revision: revision,
    );
    expect(
      plan.messages.map((item) => item['content']).join(),
      contains('对话冲突时保留沉默'),
    );
    expect(plan.usedUnits, lessThanOrEqualTo(4000));
  }
}
