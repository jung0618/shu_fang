import 'dart:convert';
import 'dart:io';

import 'safe_file_writer.dart';
import 'storage_paths.dart';

/// IDs are filenames, never arbitrary paths supplied by a record.
class PracticePaths {
  static bool validId(String id) => RegExp(r'^practice-\d{1,24}$').hasMatch(id);

  static String bookDirectory(String root, String book) {
    if (root.trim().isEmpty ||
        book.length > 255 ||
        !StoragePaths.validName(book)) {
      throw ArgumentError('工作区或作品标识无效');
    }
    return Directory('$root/books/$book').absolute.path;
  }

  static String casePath(String root, String book, String id) {
    if (!validId(id)) throw ArgumentError('练习记录标识无效');
    return '${bookDirectory(root, book)}/.practice/$id.json';
  }
}

bool _utc(Object? value) =>
    value is String &&
    value.length <= 40 &&
    value.endsWith('Z') &&
    DateTime.tryParse(value) != null;

class ConfirmedWritingPreference {
  final String id;
  final String text;
  final String sourceCaseId;
  final String confirmedAt;
  final String? revokedAt;

  const ConfirmedWritingPreference._(
    this.id,
    this.text,
    this.sourceCaseId,
    this.confirmedAt,
    this.revokedAt,
  );

  bool get active => revokedAt == null;

  factory ConfirmedWritingPreference.fromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final text = data['text'];
    final source = data['source_case_id'];
    final confirmed = data['confirmed_at'];
    final revoked = data['revoked_at'];
    if (id is! String ||
        !RegExp(r'^preference-\d{1,24}$').hasMatch(id) ||
        text is! String ||
        text.trim().isEmpty ||
        text.length > 200 ||
        source is! String ||
        !PracticePaths.validId(source) ||
        !_utc(confirmed) ||
        (revoked != null && !_utc(revoked)) ||
        (revoked is String &&
            DateTime.parse(
              revoked,
            ).isBefore(DateTime.parse(confirmed as String)))) {
      throw const FormatException('作者确认偏好格式无效');
    }
    return ConfirmedWritingPreference._(
      id,
      text,
      source,
      confirmed as String,
      revoked as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'source_case_id': sourceCaseId,
    'confirmed_at': confirmedAt,
    'revoked_at': revokedAt,
  };
}

class WritingPreferences {
  final String book;
  final int version;
  final List<ConfirmedWritingPreference> items;

  WritingPreferences._(
    this.book,
    this.version,
    List<ConfirmedWritingPreference> items,
  ) : items = List.unmodifiable(items);

  factory WritingPreferences.empty(String book) =>
      WritingPreferences._(book, 0, []);

  factory WritingPreferences.fromJson(Map<String, dynamic> data) {
    final book = data['book'];
    final version = data['version'];
    final raw = data['items'];
    if (data['schema_version'] != 1 ||
        data['origin'] != 'author_confirmed' ||
        book is! String ||
        book.length > 255 ||
        !StoragePaths.validName(book) ||
        version is! int ||
        version < 0 ||
        raw is! List ||
        raw.length > 200) {
      throw const FormatException('作品偏好文件格式无效');
    }
    final items =
        raw.map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('偏好条目无效');
          }
          return ConfirmedWritingPreference.fromJson(item);
        }).toList();
    if (items.map((item) => item.id).toSet().length != items.length ||
        items.where((item) => item.active).length > 8 ||
        (version == 0 && items.isNotEmpty)) {
      throw const FormatException('偏好条目重复或超过当前容量');
    }
    return WritingPreferences._(book, version, items);
  }

  List<ConfirmedWritingPreference> get active =>
      List.unmodifiable(items.where((item) => item.active));

  /// Old practice records retain their frozen active set. Revoked text is not
  /// included in any new request or case snapshot.
  WritingPreferences get snapshot =>
      WritingPreferences._(book, version, active);

  Map<String, Object> toJson() => {
    'schema_version': 1,
    'origin': 'author_confirmed',
    'book': book,
    'version': version,
    'items': items.map((item) => item.toJson()).toList(),
  };

  Map<String, Object> get requestData => {
    'kind': 'author_confirmed_preferences',
    ...snapshot.toJson(),
  };
}

class WritingPreferenceStore {
  static final Map<String, Future<void>> _pending = {};
  static int _lastId = 0;

  static String pathFor(String root, String book) =>
      '${PracticePaths.bookDirectory(root, book)}/.writing-preferences.json';

  static Future<WritingPreferences> load(String root, String book) async {
    final file = File(pathFor(root, book));
    if (!await file.exists()) return WritingPreferences.empty(book);
    if (await file.length() > 240000) throw const FormatException('作品偏好文件过大');
    final data = jsonDecode(await file.readAsString());
    if (data is! Map<String, dynamic>) throw const FormatException('作品偏好文件无效');
    final preferences = WritingPreferences.fromJson(data);
    if (preferences.book != book) throw const FormatException('偏好不属于当前作品');
    return preferences;
  }

  /// The author supplies the text. Selecting try/reject in a practice does not
  /// call this API. A source case must exist in this exact workspace and book.
  static Future<WritingPreferences> confirm({
    required String root,
    required String book,
    required int expectedVersion,
    required String sourceCaseId,
    required String text,
  }) => _change(root, book, expectedVersion, (previous) async {
    final file = File(PracticePaths.casePath(root, book, sourceCaseId));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() > 160000) {
      throw const FormatException('来源练习不存在或无法读取');
    }
    final source = jsonDecode(await file.readAsString());
    if (source is! Map<String, dynamic> ||
        ![1, 2, 3].contains(source['schema_version']) ||
        source['id'] != sourceCaseId ||
        source['book'] != book ||
        source['workspace_root'] != Directory(root).absolute.path ||
        source['evidence_status'] != 'author_recorded_unassessed' ||
        source['promoted_to_preference'] != false) {
      throw const FormatException('来源练习范围或格式无效');
    }
    if (previous.items.length >= 200) {
      throw StateError('当前已达 200 项偏好历史的容量上限，暂时无法添加。原记录仍保留。');
    }
    if (previous.active.length >= 8) {
      throw StateError('当前最多保留 8 项生效偏好，请先撤销不再适用的偏好。');
    }
    final normalized = text.trim();
    if (previous.active.any((item) => item.text == normalized)) {
      throw StateError('这项偏好已经生效');
    }
    final now = DateTime.now().microsecondsSinceEpoch;
    _lastId = now > _lastId ? now : _lastId + 1;
    return [
      ...previous.items,
      ConfirmedWritingPreference.fromJson({
        'id': 'preference-$_lastId',
        'text': normalized,
        'source_case_id': sourceCaseId,
        'confirmed_at': DateTime.now().toUtc().toIso8601String(),
        'revoked_at': null,
      }),
    ];
  });

  static Future<WritingPreferences> revoke({
    required String root,
    required String book,
    required int expectedVersion,
    required String id,
  }) => _change(root, book, expectedVersion, (previous) async {
    if (!previous.items.any((item) => item.id == id && item.active)) {
      throw StateError('这项偏好不存在或已经撤销，请重新载入');
    }
    return previous.items
        .map(
          (item) =>
              item.id == id
                  ? ConfirmedWritingPreference.fromJson({
                    ...item.toJson(),
                    'revoked_at': DateTime.now().toUtc().toIso8601String(),
                  })
                  : item,
        )
        .toList();
  });

  static Future<WritingPreferences> _change(
    String root,
    String book,
    int expectedVersion,
    Future<List<ConfirmedWritingPreference>> Function(WritingPreferences)
    update,
  ) {
    final path = pathFor(root, book);
    final operation = (_pending[path] ?? Future<void>.value()).then((_) async {
      final previous = await load(root, book);
      if (previous.version != expectedVersion) {
        throw StateError('作品偏好已有更新，请重新载入后再操作');
      }
      final items = await update(previous);
      final next = WritingPreferences.fromJson({
        ...previous.toJson(),
        'version': previous.version + 1,
        'items': items.map((item) => item.toJson()).toList(),
      });
      await SafeFileWriter.writeText(
        path,
        const JsonEncoder.withIndent('  ').convert(next.toJson()),
        keepPrevious: true,
      );
      return next;
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
