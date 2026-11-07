import 'dart:convert';
import 'dart:io';

import 'safe_file_writer.dart';
import 'storage_paths.dart';

/// An author's explicit choice for one book. Observations cannot create this.
class AuthorWritingGoal {
  final String book;
  final int version;
  final bool enabled;
  final String target;
  final String keep;
  final String avoid;
  final String updatedAt;

  const AuthorWritingGoal._({
    required this.book,
    required this.version,
    required this.enabled,
    required this.target,
    required this.keep,
    required this.avoid,
    required this.updatedAt,
  });

  factory AuthorWritingGoal.fromJson(Map<String, dynamic> data) {
    String field(String key, int limit) {
      final value = data[key];
      if (value is! String || value.length > limit) {
        throw FormatException('作品目标字段 $key 无效');
      }
      return value;
    }

    final book = field('book', 255);
    final version = data['version'];
    final enabled = data['enabled'];
    final target = field('target', 400);
    final keep = field('keep', 300);
    final avoid = field('avoid', 300);
    final updatedAt = field('updated_at', 40);
    if (data['schema_version'] != 1 ||
        data['origin'] != 'author_explicit' ||
        !StoragePaths.validName(book) ||
        version is! int ||
        version < 1 ||
        enabled is! bool ||
        target.trim().isEmpty ||
        !updatedAt.endsWith('Z') ||
        DateTime.tryParse(updatedAt) == null) {
      throw const FormatException('作品目标记录无效，请先检查原文件');
    }
    return AuthorWritingGoal._(
      book: book,
      version: version,
      enabled: enabled,
      target: target,
      keep: keep,
      avoid: avoid,
      updatedAt: updatedAt,
    );
  }

  Map<String, Object> toJson() => {
    'schema_version': 1,
    'origin': 'author_explicit',
    'book': book,
    'version': version,
    'enabled': enabled,
    'target': target,
    'keep': keep,
    'avoid': avoid,
    'updated_at': updatedAt,
  };

  /// Used as labelled request data, never as a system instruction. A disabled
  /// goal's old text must not influence a new request.
  String get requestData => jsonEncode(
    enabled
        ? {'kind': 'author_writing_goal', ...toJson()}
        : {'kind': 'author_writing_goal', 'enabled': false},
  );
}

class WritingGoalStore {
  static final Map<String, Future<void>> _pending = {};

  static String pathFor({required String root, required String book}) {
    if (root.trim().isEmpty || !StoragePaths.validName(book)) {
      throw ArgumentError('工作区或作品标识无效');
    }
    return File(
      '$root${Platform.pathSeparator}books${Platform.pathSeparator}'
      '$book${Platform.pathSeparator}.writing-goal.json',
    ).absolute.path;
  }

  static Future<AuthorWritingGoal?> load({
    required String root,
    required String book,
  }) async {
    final file = File(pathFor(root: root, book: book));
    if (!await file.exists()) return null;
    if (await file.length() > 16000) {
      throw const FormatException('作品目标文件过大，请先检查原文件');
    }
    final data = jsonDecode(await file.readAsString());
    if (data is! Map<String, dynamic>) {
      throw const FormatException('作品目标格式无效');
    }
    final goal = AuthorWritingGoal.fromJson(data);
    if (goal.book != book) throw const FormatException('作品目标不属于当前作品');
    return goal;
  }

  /// The read/version check/write is serialized within this process. Other
  /// processes are outside this local store's concurrency contract.
  static Future<AuthorWritingGoal> save({
    required String root,
    required String book,
    required int? expectedVersion,
    required String target,
    required String keep,
    required String avoid,
    bool enabled = true,
  }) {
    final path = pathFor(root: root, book: book);
    final operation = (_pending[path] ?? Future<void>.value()).then((_) async {
      final previous = await load(root: root, book: book);
      if (previous?.version != expectedVersion) {
        throw StateError('作品目标已有更新，请重新载入后再保存');
      }
      final goal = AuthorWritingGoal.fromJson({
        'schema_version': 1,
        'origin': 'author_explicit',
        'book': book,
        'version': (previous?.version ?? 0) + 1,
        'enabled': enabled,
        'target': target.trim(),
        'keep': keep.trim(),
        'avoid': avoid.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await SafeFileWriter.writeText(
        path,
        const JsonEncoder.withIndent('  ').convert(goal.toJson()),
        keepPrevious: true,
      );
      return goal;
    });
    final settled = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _pending[path] = settled;
    settled.then((_) {
      if (identical(_pending[path], settled)) _pending.remove(path);
    });
    return operation;
  }
}
