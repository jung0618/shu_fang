import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';

import '../store/local_data_source.dart';
import 'editor_context_capture.dart';
import 'writing_context.dart';
import 'writing_request_ledger.dart';

enum CandidateOperation { replaceSelection, appendToChapter }

/// A read-only comparison, never an instruction to write or learn.
class WritingCandidate {
  final EditorSourceSnapshot source;
  final WritingRequestCompletion completion;
  final String directionKey;
  final String body;
  final String baseSha256;
  final CandidateOperation operation;
  final int start;
  final int end;

  WritingCandidate._(
    this.source,
    this.completion,
    this.directionKey,
    this.body,
    this.operation,
    this.start,
    this.end,
  ) : baseSha256 = fingerprint(source.text);

  String get id => 'comparison-${completion.requestId}';
  String get before => source.text.substring(start, end);
  late final CandidateDifference difference = CandidateDifference.between(
    before,
    body,
  );

  static String fingerprint(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  static WritingCandidate? fromCompleted({
    required EditorSourceSnapshot source,
    required WritingContextPlan plan,
    required WritingRequestCompletion completion,
    required String body,
  }) {
    if (completion.root != source.root ||
        completion.book != source.book ||
        completion.chapter != source.chapter ||
        completion.sourceId != source.id ||
        plan.sourceId != source.id ||
        plan.book != source.book ||
        plan.chapter != source.chapter ||
        completion.task != plan.task.name ||
        completion.contextSha256 != fingerprint(jsonEncode(plan.toPacket())) ||
        completion.outputUnits != body.length ||
        completion.outputSha256 != fingerprint(body) ||
        body.trim().isEmpty ||
        body.length > 128000 ||
        plan.directionKey == null) {
      throw StateError('回复与原请求不一致，不能创建比较。');
    }
    final start = source.selectionStart;
    final end = source.selectionEnd;
    if (source.text.length > 512000) return null;
    if (plan.task == WritingTask.revision) {
      if (start == null || end == null) return null;
      if (start < 0 ||
          end <= start ||
          end > source.text.length ||
          !_boundary(source.text, start) ||
          !_boundary(source.text, end)) {
        return null;
      }
      return WritingCandidate._(
        source,
        completion,
        plan.directionKey!,
        body,
        CandidateOperation.replaceSelection,
        start,
        end,
      );
    }
    if (plan.task == WritingTask.continuation) {
      return WritingCandidate._(
        source,
        completion,
        plan.directionKey!,
        body,
        CandidateOperation.appendToChapter,
        source.text.length,
        source.text.length,
      );
    }
    return null;
  }
}

/// Watches the frozen editor from before dispatch, including edit-and-revert.
/// The panel owns this watch; historic chat text does not recreate it.
class CandidateOriginWatch extends ChangeNotifier {
  final EditorSourceSnapshot source;
  final TextEditingController controller;
  String? _invalidReason;
  String? get invalidReason => _invalidReason;

  CandidateOriginWatch(this.source, this.controller) {
    controller.addListener(_checkEditor);
    localDataSource.sessionChanges.addListener(_checkSession);
    _checkEditor();
    _checkSession();
  }

  void invalidate(String reason) {
    if (_invalidReason != null) return;
    _invalidReason = reason;
    notifyListeners();
  }

  void _checkEditor() {
    if (controller.text != source.text) {
      invalidate('正文已变化；这份比较已失效，请保留回复或重新发起写作。');
    } else if (controller.value.composing.isValid &&
        !controller.value.composing.isCollapsed) {
      invalidate('输入法正在组字；这份比较已失效，请完成输入后重新发起写作。');
    }
  }

  void _checkSession() {
    if (source.sessionRevision != localDataSource.sessionRevision ||
        source.root != localDataSource.storageRoot) {
      invalidate('工作区或会话已切换；旧比较已隐藏。');
    }
  }

  @override
  void dispose() {
    controller.removeListener(_checkEditor);
    localDataSource.sessionChanges.removeListener(_checkSession);
    super.dispose();
  }
}

bool _boundary(String text, int offset) =>
    offset == 0 ||
    offset == text.length ||
    !(text.codeUnitAt(offset - 1) >= 0xd800 &&
        text.codeUnitAt(offset - 1) <= 0xdbff &&
        text.codeUnitAt(offset) >= 0xdc00 &&
        text.codeUnitAt(offset) <= 0xdfff);

/// Linear comparison: disjoint edits are shown as one combined changed span.
/// Offsets never bisect an emoji or supplementary Chinese character.
class CandidateDifference {
  final String prefix;
  final String removed;
  final String added;
  final String suffix;
  const CandidateDifference._(
    this.prefix,
    this.removed,
    this.added,
    this.suffix,
  );

  factory CandidateDifference.between(String before, String after) {
    var start = 0;
    while (start < before.length &&
        start < after.length &&
        before.codeUnitAt(start) == after.codeUnitAt(start)) {
      start++;
    }
    while (!_boundary(before, start) || !_boundary(after, start)) {
      start--;
    }
    var tail = 0;
    while (tail < before.length - start &&
        tail < after.length - start &&
        before.codeUnitAt(before.length - tail - 1) ==
            after.codeUnitAt(after.length - tail - 1)) {
      tail++;
    }
    while (!_boundary(before, before.length - tail) ||
        !_boundary(after, after.length - tail)) {
      tail--;
    }
    return CandidateDifference._(
      before.substring(0, start),
      before.substring(start, before.length - tail),
      after.substring(start, after.length - tail),
      before.substring(before.length - tail),
    );
  }

  static String excerpt(String text, [int limit = 4000]) {
    if (text.length <= limit) return text;
    var end = limit;
    if (!_boundary(text, end)) end--;
    return '${text.substring(0, end)}\n…（显示已截短，请在聊天中查看完整回复）';
  }
}
