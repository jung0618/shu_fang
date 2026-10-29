import 'dart:convert';
import 'dart:io';

import 'storage_paths.dart';
import 'writing_goal.dart';
import 'writing_practice.dart';
import 'writing_preferences.dart';

/// A validated, immutable record. Reading never edits the source case.
class WritingPracticeCase {
  final String id;
  final String createdAt;
  final String book;
  final String chapter;
  final PracticeGoal goal;
  final String intention;
  final String passage;
  final String revision;
  final String reflection;
  final String decision;
  final String model;
  final PracticeFeedback feedback;
  final PracticeFeedback? revisionFeedback;
  final AuthorWritingGoal? authorGoal;
  final WritingPreferences? preferences;
  final PracticeFeedbackSource? feedbackSource;
  final PracticeFeedbackSource? revisionFeedbackSource;

  WritingPracticeCase._({
    required this.id,
    required this.createdAt,
    required this.book,
    required this.chapter,
    required this.goal,
    required this.intention,
    required this.passage,
    required this.revision,
    required this.reflection,
    required this.decision,
    required this.model,
    required this.feedback,
    required this.revisionFeedback,
    required this.authorGoal,
    required this.preferences,
    required this.feedbackSource,
    required this.revisionFeedbackSource,
  });

  factory WritingPracticeCase.fromJson(
    Map<String, dynamic> data, {
    required String root,
    required String book,
    required String id,
  }) {
    String field(String key, int limit, {bool empty = true}) {
      final value = data[key];
      if (value is! String ||
          value.length > limit ||
          (!empty && value.trim().isEmpty)) {
        throw FormatException('练习记录字段 $key 无效');
      }
      return value;
    }

    final created = field('created_at', 40, empty: false);
    final chapter = field('chapter', 255, empty: false);
    final passage = field('passage', 1800, empty: false);
    final revision = field('author_revision', 1800);
    final decision = field('author_decision', 20);
    final start = data['source_start'];
    final end = data['source_end'];
    if (!PracticePaths.supportedCaseSchemas.contains(data['schema_version']) ||
        data['id'] != id ||
        !PracticePaths.validId(id) ||
        data['book'] != book ||
        data['workspace_root'] != Directory(root).absolute.path ||
        !StoragePaths.validName(chapter) ||
        !created.endsWith('Z') ||
        DateTime.tryParse(created) == null ||
        data['offset_encoding'] != 'utf-16' ||
        start is! int ||
        end is! int ||
        start < 0 ||
        end - start != passage.length ||
        !['pending', 'try', 'reject', 'defer'].contains(decision) ||
        data['evidence_status'] != 'author_recorded_unassessed' ||
        data['promoted_to_preference'] != false) {
      throw const FormatException('练习记录范围或版本无效');
    }
    final goal =
        PracticeGoal.values
            .where((item) => item.name == data['goal'])
            .firstOrNull;
    if (goal == null) throw const FormatException('练习目标无效');
    PracticeFeedback feedback(String key, String source) {
      if (data[key] is! List) throw const FormatException('练习反馈格式无效');
      return PracticeFeedback.parse(
        jsonEncode({'observations': data[key]}),
        source,
      );
    }

    final rawGoal = data['author_goal_snapshot'];
    final authorGoal =
        rawGoal == null
            ? null
            : rawGoal is Map<String, dynamic>
            ? AuthorWritingGoal.fromJson(rawGoal)
            : throw const FormatException('记录中的作品目标无效');
    final rawPreferences = data['author_preferences_snapshot'];
    final preferences =
        rawPreferences == null
            ? null
            : rawPreferences is Map<String, dynamic>
            ? WritingPreferences.fromJson(rawPreferences)
            : throw const FormatException('记录中的作品偏好无效');
    if ((authorGoal != null && authorGoal.book != book) ||
        (preferences != null &&
            (preferences.book != book ||
                preferences.items.any((item) => !item.active)))) {
      throw const FormatException('记录中的作者方向范围无效');
    }
    PracticeFeedbackSource? source(String key, bool compare) {
      final raw = data[key];
      if (raw == null) return null;
      if (data['schema_version'] != 4 || raw is! Map<String, dynamic>) {
        throw const FormatException('练笔调用来源版本或格式无效');
      }
      final value = PracticeFeedbackSource.fromJson(raw);
      value.validateCase(data, compare: compare);
      return value;
    }

    final originalSource = source('feedback_source', false);
    final revisionSource = source('revision_feedback_source', true);
    if (originalSource != null &&
        revisionSource != null &&
        originalSource.request.requestId == revisionSource.request.requestId) {
      throw const FormatException('原稿与改稿不能共用一次调用来源');
    }
    return WritingPracticeCase._(
      id: id,
      createdAt: created,
      book: book,
      chapter: chapter,
      goal: goal,
      intention: field('intention', 400),
      passage: passage,
      revision: revision,
      reflection: field('author_reflection', 800),
      decision: decision,
      model: field('model', 200, empty: false),
      feedback: feedback('feedback', passage),
      revisionFeedback:
          data['revision_feedback'] == null
              ? null
              : feedback('revision_feedback', revision),
      authorGoal: authorGoal,
      preferences: preferences,
      feedbackSource: originalSource,
      revisionFeedbackSource: revisionSource,
    );
  }
}

class PracticeHistoryPage {
  final List<WritingPracticeCase> records;
  final List<String> problems;
  final String? nextCursor;

  PracticeHistoryPage(
    List<WritingPracticeCase> records,
    List<String> problems,
    this.nextCursor,
  ) : records = List.unmodifiable(records),
      problems = List.unmodifiable(problems);
}

class WritingPracticeHistory {
  static Future<WritingPracticeCase> loadCase(
    String root,
    String book,
    String id,
  ) async {
    final file = File(PracticePaths.casePath(root, book, id));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('练习文件不存在或不是普通文件');
    }
    if (await file.length() > 160000) throw const FormatException('练习文件过大');
    final data = jsonDecode(await file.readAsString());
    if (data is! Map<String, dynamic>) throw const FormatException('练习文件格式无效');
    return WritingPracticeCase.fromJson(data, root: root, book: book, id: id);
  }

  static int _compareIds(String a, String b) => a
      .substring(9)
      .padLeft(24, '0')
      .compareTo(b.substring(9).padLeft(24, '0'));

  /// Only filenames are scanned; bodies are read for one page. Broken records
  /// occupy a page position and are reported, so pagination cannot hide them.
  static Future<PracticeHistoryPage> loadPage(
    String root,
    String book, {
    String? beforeId,
    int pageSize = 20,
  }) async {
    if (pageSize < 1 ||
        pageSize > 50 ||
        (beforeId != null && !PracticePaths.validId(beforeId))) {
      throw ArgumentError('练习分页参数无效');
    }
    final directory = Directory(
      '${PracticePaths.bookDirectory(root, book)}/.practice',
    );
    if (!await directory.exists()) return PracticeHistoryPage([], [], null);
    final ids = <String>[];
    var scanned = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (++scanned > 10000) throw StateError('练习目录条目过多，请先整理目录后重试');
      final name = entry.uri.pathSegments.last;
      if (!name.endsWith('.json')) continue;
      final id = name.substring(0, name.length - 5);
      if (entry is File &&
          PracticePaths.validId(id) &&
          (beforeId == null || _compareIds(id, beforeId) < 0)) {
        ids.add(id);
      }
    }
    ids.sort((a, b) => _compareIds(b, a));
    final selected = ids.take(pageSize).toList();
    final records = <WritingPracticeCase>[];
    final problems = <String>[];
    for (final id in selected) {
      try {
        records.add(await loadCase(root, book, id));
      } catch (error) {
        problems.add('$id：$error');
      }
    }
    return PracticeHistoryPage(
      records,
      problems,
      ids.length > selected.length ? selected.last : null,
    );
  }
}
