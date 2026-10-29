import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/practice_learning_view.dart';
import 'package:shufang_flutter/services/writing_preferences.dart';

import 'support/practice_fixture.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shufang-learning-');
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<PracticeLearningView> load() =>
      PracticeLearningView.load(directory.path, '测试作品', 'practice-100');

  Future<WritingPreferences> confirm({
    int version = 0,
    String id = 'practice-100',
    String text = '争执时保留停顿',
  }) => WritingPreferenceStore.confirm(
    root: directory.path,
    book: '测试作品',
    expectedVersion: version,
    sourceCaseId: id,
    text: text,
  );

  test('every case schema is reviewable without inventing a source', () async {
    for (final schema in [1, 2, 3, 4]) {
      final file = await writePracticeFixture(directory.path, schema: schema);
      final before = await file.readAsBytes();
      final view = await load();
      expect(view.record.id, 'practice-100');
      expect(view.candidates.single.hasStoredSource, isFalse);
      expect(view.confirmed, isEmpty);
      expect(view.revoked, isEmpty);
      expect(await file.readAsBytes(), before);
      expect(
        await File(
          WritingPreferenceStore.pathFor(directory.path, '测试作品'),
        ).exists(),
        isFalse,
      );
    }
  });

  test(
    'author decisions never promote model directions or reflections',
    () async {
      for (final decision in ['pending', 'try', 'reject', 'defer']) {
        await writePracticeFixture(
          directory.path,
          changes: {'author_decision': decision},
        );
        final view = await load();
        expect(view.record.decision, decision);
        expect(view.record.reflection, isNotEmpty);
        expect(view.candidates.single.observation.direction, '尝试一个更贴近处境的动作');
        expect(view.confirmed, isEmpty);
      }
    },
  );

  test(
    'revocation cannot be revived by a frozen preference snapshot',
    () async {
      await writePracticeFixture(directory.path);
      final first = await confirm();
      final file = await writePracticeFixture(
        directory.path,
        schema: 4,
        changes: {'author_preferences_snapshot': first.snapshot.toJson()},
      );
      final before = await file.readAsBytes();
      final confirmed = await load();
      expect(confirmed.confirmed.single.text, '争执时保留停顿');
      await WritingPreferenceStore.revoke(
        root: directory.path,
        book: '测试作品',
        expectedVersion: 1,
        id: first.active.single.id,
      );
      final revoked = await load();
      expect(revoked.preferenceVersion, 2);
      expect(revoked.confirmed, isEmpty);
      expect(revoked.revoked.single.text, '争执时保留停顿');
      expect(revoked.record.preferences!.active, hasLength(1));
      expect(
        confirmed.confirmed,
        hasLength(1),
      ); // Old views are explicit snapshots.
      expect(await file.readAsBytes(), before);
    },
  );

  test('current confirmation is scoped to this source case and book', () async {
    await writePracticeFixture(directory.path);
    await writePracticeFixture(directory.path, id: 'practice-101');
    await confirm(id: 'practice-101');
    final first = await load();
    expect(first.preferenceVersion, 1);
    expect(first.confirmed, isEmpty);
    await confirm(version: 1, text: '只确认作者自己填写的表述');
    final second = await load();
    expect(second.confirmed.single.text, '只确认作者自己填写的表述');
    expect(
      second.candidates.single.observation.direction,
      isNot(second.confirmed.single.text),
    );
    await expectLater(
      PracticeLearningView.load(directory.path, '另一作品', 'practice-100'),
      throwsFormatException,
    );
  });

  test(
    'original and revision suggestions remain separate model candidates',
    () async {
      await writePracticeFixture(
        directory.path,
        schema: 4,
        changes: {
          'revision_feedback': [
            {
              'quote': '他握着杯子',
              'observation': '动作明确',
              'reason': '贴合本次意图',
              'direction': '尝试改变停顿的位置',
              'exercise': '再写一句',
              'example': '',
            },
          ],
        },
      );
      final view = await load();
      expect(view.candidates.map((item) => item.fromRevision), [false, true]);
      expect(view.candidates.last.observation.quote, '他握着杯子');
      expect(view.confirmed, isEmpty);
      expect(() => view.candidates.clear(), throwsUnsupportedError);
      expect(() => view.confirmed.clear(), throwsUnsupportedError);
      expect(() => view.revoked.clear(), throwsUnsupportedError);
    },
  );

  test(
    'broken and foreign cases cannot produce a review or alter evidence',
    () async {
      for (final change in <Map<String, dynamic>>[
        {'schema_version': 99},
        {'book': '另一作品'},
        {'workspace_root': '${directory.path}/outside'},
        {'source_end': 999},
        {
          'feedback_source': {'request_id': 'invented'},
        },
      ]) {
        final file = await writePracticeFixture(
          directory.path,
          schema: 4,
          changes: change,
        );
        final before = await file.readAsBytes();
        await expectLater(load(), throwsFormatException);
        expect(await file.readAsBytes(), before);
      }
    },
  );

  test(
    'a damaged preference store fails closed instead of using case snapshots',
    () async {
      await writePracticeFixture(directory.path);
      final confirmed = await confirm();
      await writePracticeFixture(
        directory.path,
        changes: {'author_preferences_snapshot': confirmed.snapshot.toJson()},
      );
      final file = File(WritingPreferenceStore.pathFor(directory.path, '测试作品'));
      for (final raw in [
        '{broken',
        jsonEncode(WritingPreferences.empty('另一作品').toJson()),
      ]) {
        await file.writeAsString(raw);
        await expectLater(load(), throwsFormatException);
        expect(await file.readAsString(), raw);
      }
    },
  );
}
