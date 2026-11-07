import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'storage_paths.dart';
import 'writing_goal.dart';
import 'writing_preferences.dart';

/// Frozen author choices for a new request. No observations or practice text
/// are loaded here. The workspace identity stays local to the history key.
class WritingDirectionSnapshot {
  final String root;
  final String book;
  final AuthorWritingGoal? goal;
  final WritingPreferences preferences;

  WritingDirectionSnapshot({
    required String root,
    required this.book,
    required this.goal,
    required WritingPreferences preferences,
  }) : root = Directory(root).absolute.path,
       preferences = preferences.snapshot {
    if (root.trim().isEmpty ||
        !StoragePaths.validName(book) ||
        book.length > 255 ||
        (goal != null && goal!.book != book) ||
        preferences.book != book) {
      throw ArgumentError('作者方向不属于当前工作区或作品');
    }
  }

  static Future<WritingDirectionSnapshot> load({
    required String root,
    required String book,
  }) async {
    final goal = await WritingGoalStore.load(root: root, book: book);
    final preferences = await WritingPreferenceStore.load(root, book);
    return WritingDirectionSnapshot(
      root: root,
      book: book,
      goal: goal,
      preferences: preferences,
    );
  }

  String get requestData => jsonEncode({
    'kind': 'author_direction_snapshot',
    'schema_version': 1,
    'book': book,
    'goal_version': goal?.version,
    'author_goal':
        goal == null
            ? {'kind': 'author_writing_goal', 'enabled': false}
            : jsonDecode(goal!.requestData),
    'confirmed_preferences': preferences.requestData,
  });

  /// A changed goal, preference version or workspace starts a new context
  /// segment. Returning to old wording does not revive old conversations.
  String get historyKey =>
      sha256.convert(utf8.encode(jsonEncode([root, requestData]))).toString();

  String get description =>
      '${goal?.enabled == true ? "已参考作品目标" : "未启用作品目标"}，'
      '${preferences.active.length} 项确认偏好。';
}
