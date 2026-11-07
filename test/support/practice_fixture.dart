import 'dart:convert';
import 'dart:io';

import 'package:shufang_flutter/services/writing_preferences.dart';

const fixturePassage = '他把杯子推远，又看了看门口。';

Map<String, dynamic> practiceFixture(
  String root, {
  String book = '测试作品',
  String id = 'practice-100',
  int schema = 3,
}) => {
  'schema_version': schema,
  'id': id,
  'created_at': '2026-10-28T00:00:00.000Z',
  'source_id': 'draft-100',
  'workspace_root': Directory(root).absolute.path,
  'book': book,
  'chapter': '第一章',
  'source_start': 2,
  'source_end': 2 + fixturePassage.length,
  'offset_encoding': 'utf-16',
  'passage': fixturePassage,
  'goal': 'dialogue',
  'intention': '让人物欲言又止',
  'feedback': [
    {
      'quote': '他把杯子推远',
      'observation': '动作带着迟疑',
      'reason': '符合保留情绪的意图',
      'direction': '尝试一个更贴近处境的动作',
      'exercise': '自行改写一句',
      'example': '',
      'offsets_in_passage': [0],
    },
  ],
  'model': 'offline-fixture',
  'author_revision': '他握着杯子，望向门口。',
  'author_reflection': '这次希望保留沉默',
  'author_decision': 'try',
  'evidence_status': 'author_recorded_unassessed',
  'promoted_to_preference': false,
};

Future<File> writePracticeFixture(
  String root, {
  String book = '测试作品',
  String id = 'practice-100',
  int schema = 3,
  Map<String, dynamic> changes = const {},
}) async {
  final file = File(PracticePaths.casePath(root, book, id));
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode({
      ...practiceFixture(root, book: book, id: id, schema: schema),
      ...changes,
    }),
  );
  return file;
}
