import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'writing_context.dart';

/// Local evidence, not a provider bill or a server-side idempotency guarantee.
/// Each request owns an append-only journal. Readers never repair originals.
class WritingRequestLedger {
  static final Set<String> _active = {};
  static final Random _random = Random.secure();
  static final _idPattern = RegExp(r'^\d{16}-[a-f0-9]{32}$');

  static Directory directory(String root) => Directory(
    '$root${Platform.pathSeparator}.shufang'
    '${Platform.pathSeparator}requests',
  );

  static Future<WritingRequestRun> begin({
    required String root,
    required WritingContextPlan plan,
    required String model,
    required bool useEngine,
  }) async {
    final canonicalRoot = await Directory(root).resolveSymbolicLinks();
    final now = DateTime.now().toUtc();
    final suffix =
        List.generate(
          16,
          (_) => _random.nextInt(256),
        ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    final id =
        '${now.microsecondsSinceEpoch.toString().padLeft(16, '0')}-$suffix';
    final dir = directory(canonicalRoot);
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$id.jsonl');
    if (await file.exists()) throw StateError('请求标识冲突，未发送。');
    final run = WritingRequestRun._(id, file);
    await run._append('prepared', {
      'workspace_root': canonicalRoot,
      'book': plan.book,
      'chapter': plan.chapter,
      'source_id': plan.sourceId,
      'task': plan.task.name,
      'requested_model': model,
      'route': useEngine ? 'engine' : 'direct',
      'context_sha256':
          sha256.convert(utf8.encode(jsonEncode(plan.toPacket()))).toString(),
      'context_version': 1,
      'budget_units': plan.budget,
      'used_units': plan.usedUnits,
      'source_units': plan.sourceUnits,
      'total_source_units': plan.totalSourceUnits,
      'history_turns': plan.historyTurns,
      'omitted_turns': plan.omittedTurns,
      'partial': plan.partial,
      'unit': 'utf-16',
      'temperature': 0.7,
    });
    _active.add(id);
    return run;
  }

  /// Cursor is the last request ID, newest first. Corrupt evidence remains
  /// visible as a problem and is never rewritten or interpreted as success.
  static Future<WritingRequestPage> read(
    String root, {
    String? cursor,
    int limit = 30,
  }) async {
    if (limit < 1 ||
        limit > 100 ||
        (cursor != null && !_idPattern.hasMatch(cursor))) {
      throw ArgumentError('请求记录分页范围无效');
    }
    final dir = directory(root);
    if (!await dir.exists()) return WritingRequestPage([], [], null);
    final files = <File>[];
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is File && entry.path.endsWith('.jsonl')) files.add(entry);
    }
    String id(File file) =>
        file.uri.pathSegments.last.replaceFirst(RegExp(r'\.jsonl$'), '');
    files.sort((a, b) => id(b).compareTo(id(a)));
    final eligible =
        files
            .where((f) => cursor == null || id(f).compareTo(cursor) < 0)
            .toList();
    final selected = eligible.take(limit).toList();
    final records = <WritingRequestRecord>[];
    final problems = <String>[];
    for (final file in selected) {
      final requestId = id(file);
      try {
        if (!_idPattern.hasMatch(requestId) ||
            await file.length() > 128 * 1024) {
          throw const FormatException('文件名或大小无效');
        }
        final lines = (await file.readAsString()).split('\n');
        final events = <Map<String, dynamic>>[];
        var damaged = false;
        for (final line in lines) {
          if (line.isEmpty) continue;
          try {
            final event = jsonDecode(line) as Map<String, dynamic>;
            if (event['schema_version'] != 1 ||
                event['request_id'] != requestId ||
                event['seq'] != events.length ||
                event['data'] is! Map<String, dynamic> ||
                event['at'] is! String ||
                DateTime.tryParse(event['at']) == null ||
                (events.isEmpty
                    ? event['state'] != 'prepared'
                    : !WritingRequestRun._canFollow(
                      events.last['state'],
                      event['state'],
                    ))) {
              throw const FormatException('事件顺序或版本无效');
            }
            events.add(event);
          } catch (_) {
            damaged = true;
            problems.add('$requestId：部分记录无法读取，保留原文件；状态可能不完整。');
            break;
          }
        }
        if (events.isEmpty) throw const FormatException('缺少请求记录');
        final meta = events.first['data'] as Map<String, dynamic>;
        final actual = await Directory(root).resolveSymbolicLinks();
        if (meta['workspace_root'] != actual ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch('${meta['context_sha256']}') ||
            meta['book'] is! String ||
            meta['chapter'] is! String ||
            meta['requested_model'] is! String ||
            !['engine', 'direct'].contains(meta['route'])) {
          throw const FormatException('工作区或请求资料无效');
        }
        records.add(
          WritingRequestRecord._(
            requestId,
            events,
            _active.contains(requestId),
            damaged,
          ),
        );
      } catch (_) {
        problems.add('$requestId：记录无法读取，保留原文件。');
      }
    }
    return WritingRequestPage(
      records,
      problems,
      eligible.length > selected.length ? id(selected.last) : null,
    );
  }
}

class WritingRequestRun {
  final String id;
  final File file;
  int _seq = 0;
  String _state = '';
  bool get dispatched => _state == 'dispatching';
  bool get terminal => ['completed', 'failed', 'interrupted'].contains(_state);
  WritingRequestRun._(this.id, this.file);

  static bool _canFollow(dynamic previous, dynamic next) =>
      (previous == 'prepared' &&
          ['dispatching', 'interrupted'].contains(next)) ||
      (previous == 'dispatching' &&
          ['completed', 'failed', 'interrupted'].contains(next));

  Future<void> _append(String state, Map<String, dynamic> data) async {
    if (_state.isNotEmpty && !_canFollow(_state, state)) {
      throw StateError('请求状态转换无效');
    }
    await file.writeAsString(
      '${jsonEncode({'schema_version': 1, 'request_id': id, 'seq': _seq, 'at': DateTime.now().toUtc().toIso8601String(), 'state': state, 'data': data})}\n',
      mode: FileMode.append,
      flush: true,
    );
    _seq++;
    _state = state;
  }

  Future<void> dispatch() => _append('dispatching', {});

  Future<void> finish(
    String state, {
    String output = '',
    Map<String, dynamic> receipt = const {},
  }) async {
    try {
      await _append(state, {
        'output_units': output.length,
        'output_sha256': sha256.convert(utf8.encode(output)).toString(),
        ...providerReceipt(receipt),
        // A completed reply does not establish its price or author acceptance.
        'settlement': 'unknown', 'cost': null, 'currency': null,
      });
    } finally {
      WritingRequestLedger._active.remove(id);
    }
  }

  /// Only explicit provider counts survive. Invalid/partial reports never
  /// manufacture a zero or calculate a total from unlike measurements.
  static Map<String, dynamic> providerReceipt(Map<String, dynamic> raw) {
    final usage = raw['usage'];
    final counts = <String, int>{};
    if (usage is Map) {
      for (final key in [
        'prompt_tokens',
        'completion_tokens',
        'total_tokens',
      ]) {
        final value = usage[key];
        if (value is int && value >= 0) counts[key] = value;
      }
    }
    String? label(String key) {
      final value = raw[key];
      return value is String && value.length <= 200 ? value : null;
    }

    return {
      'provider_request_id': label('id'),
      'observed_model': label('model'),
      'finish_reason': label('finish_reason'),
      'usage_source': counts.isEmpty ? 'unknown' : 'provider_reported',
      'usage': counts.isEmpty ? null : counts,
    };
  }
}

class WritingRequestRecord {
  final String id;
  final List<Map<String, dynamic>> events;
  final bool active;
  final bool damaged;
  WritingRequestRecord._(
    this.id,
    List<Map<String, dynamic>> events,
    this.active,
    this.damaged,
  ) : events = List.unmodifiable(events);
  Map<String, dynamic> get meta => events.first['data'] as Map<String, dynamic>;
  Map<String, dynamic> get result =>
      events.last['data'] as Map<String, dynamic>;
  String get state => events.last['state'] as String;
  String get createdAt => events.first['at'] as String;
  String get statusLabel =>
      damaged
          ? '记录不完整'
          : switch (state) {
            'completed' => '回复已收齐',
            'failed' => '生成未完成',
            'interrupted' => '本地接收已中断',
            _ => active ? '正在处理' : '未见完成回执',
          };
}

class WritingRequestPage {
  final List<WritingRequestRecord> records;
  final List<String> problems;
  final String? nextCursor;
  WritingRequestPage(
    List<WritingRequestRecord> records,
    List<String> problems,
    this.nextCursor,
  ) : records = List.unmodifiable(records),
      problems = List.unmodifiable(problems);
}
