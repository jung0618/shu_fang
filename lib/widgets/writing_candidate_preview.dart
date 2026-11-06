import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/writing_candidate.dart';
import '../store/editor_store.dart';

/// Candidate preparation is local and temporary; no manuscript write or learning.
class WritingCandidatePreview extends ConsumerStatefulWidget {
  final WritingCandidate candidate;
  final CandidateOriginWatch origin;
  const WritingCandidatePreview({
    super.key,
    required this.candidate,
    required this.origin,
  });

  @override
  ConsumerState<WritingCandidatePreview> createState() =>
      _WritingCandidatePreviewState();
}

class _WritingCandidatePreviewState
    extends ConsumerState<WritingCandidatePreview> {
  bool _checking = true;
  String? _directionProblem;
  final _text = TextEditingController();
  bool _editing = false;
  bool _rangeConfirmed = false;
  bool _reviewing = false;
  int _revision = 0;
  TextSelection? _replySelection;
  CandidateTextPreview? _prepared;
  CandidateDiskObservation? _disk;
  String? _textProblem;
  String _lastText = '';
  TextRange _lastComposing = TextRange.empty;

  @override
  void initState() {
    super.initState();
    _text.addListener(_textChanged);
    _checkDirection();
  }

  void _textChanged() {
    if (_text.text == _lastText && _text.value.composing == _lastComposing) {
      return;
    }
    _lastText = _text.text;
    _lastComposing = _text.value.composing;
    setState(() {
      _revision++;
      _rangeConfirmed = false;
      _prepared = null;
      _disk = null;
      _textProblem = null;
    });
  }

  @override
  void dispose() {
    _text.removeListener(_textChanged);
    _text.dispose();
    super.dispose();
  }

  String? _currentProblem() {
    final source = widget.candidate.source;
    final handle = ref.read(editorControllerProvider);
    return widget.origin.invalidReason ??
        (ref.read(currentBookProvider) != source.book ||
                ref.read(currentChapterProvider) != source.chapter ||
                handle?.address.root != source.root ||
                handle?.address.book != source.book ||
                handle?.address.chapter != source.chapter ||
                !identical(handle?.controller, widget.origin.controller)
            ? '章节或编辑器已切换；旧比较已隐藏。'
            : _directionProblem);
  }

  Future<void> _reviewText() async {
    if (_reviewing ||
        !_rangeConfirmed ||
        _currentProblem() != null ||
        !_text.value.composing.isCollapsed) {
      return;
    }
    final revision = _revision;
    late CandidateTextPreview prepared;
    try {
      prepared = widget.candidate.prepareText(_text.text);
    } on ArgumentError catch (error) {
      setState(() => _textProblem = error.message.toString());
      return;
    }
    setState(() {
      _reviewing = true;
      _prepared = null;
      _disk = null;
    });
    try {
      final direction = await widget.candidate.source.loadDirection();
      final disk = await widget.candidate.inspectDisk();
      if (!mounted || revision != _revision || _currentProblem() != null) {
        return;
      }
      setState(() {
        if (direction.historyKey != widget.candidate.directionKey) {
          _directionProblem = '作者方向已变化；请按新方向重新发起写作。';
        } else {
          _prepared = prepared;
          _disk = disk;
        }
      });
    } catch (_) {
      if (mounted && revision == _revision && _currentProblem() == null) {
        setState(() => _textProblem = '暂时无法完成本机核对，请保留候选正文。');
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  Future<void> _checkDirection() async {
    try {
      final direction = await widget.candidate.source.loadDirection();
      if (!mounted) return;
      setState(() {
        _checking = false;
        if (direction.historyKey != widget.candidate.directionKey) {
          _directionProblem = '作者方向已变化；请按新方向重新发起写作。';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _checking = false;
          _directionProblem = '暂时无法核对当前作者方向，比较内容已隐藏。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(currentBookProvider);
    final chapter = ref.watch(currentChapterProvider);
    final handle = ref.watch(editorControllerProvider);
    final candidate = widget.candidate;
    final source = candidate.source;
    return AnimatedBuilder(
      animation: widget.origin,
      builder: (context, child) {
        final problem =
            widget.origin.invalidReason ??
            (book != source.book ||
                    chapter != source.chapter ||
                    handle?.address.root != source.root ||
                    handle?.address.book != source.book ||
                    handle?.address.chapter != source.chapter ||
                    !identical(handle?.controller, widget.origin.controller)
                ? '章节或编辑器已切换；旧比较已隐藏。'
                : _directionProblem);
        final diff = _prepared?.difference ?? candidate.difference;
        return AlertDialog(
          title: const Text('改稿比较'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('只读预览 · 尚未写入原稿'),
                  const SizedBox(height: 12),
                  if (problem != null)
                    Text(problem)
                  else if (_checking)
                    const Text('正在核对作者方向…')
                  else ...[
                    Text('${source.book} / ${source.chapter}'),
                    const SizedBox(height: 8),
                    Text(
                      candidate.operation == CandidateOperation.replaceSelection
                          ? '比较范围：发送时的原选区（${candidate.before.length} 字符）'
                          : '比较范围：章节末尾插入；不替换已有正文',
                    ),
                    const SizedBox(height: 8),
                    if (!_editing) ...[
                      const Text('整份回复作为比较内容，可能包含模型说明；未自动提取正文。多处变化合并显示。'),
                      OutlinedButton(
                        onPressed: () => setState(() => _editing = true),
                        child: const Text('整理候选正文'),
                      ),
                    ] else ...[
                      const Text('只放入你想使用的正文，可从回复选取或自行编辑。原稿与完整回复均保持原样。'),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('从完整回复中选取'),
                        children: [
                          SelectableText(
                            candidate.body,
                            onSelectionChanged:
                                (selection, cause) =>
                                    setState(() => _replySelection = selection),
                          ),
                          TextButton(
                            onPressed:
                                _replySelection == null ||
                                        !_replySelection!.isValid ||
                                        _replySelection!.isCollapsed
                                    ? null
                                    : () {
                                      final selection = _replySelection!;
                                      _text.text = candidate.body.substring(
                                        selection.start,
                                        selection.end,
                                      );
                                    },
                            child: const Text('将所选文字放入候选'),
                          ),
                        ],
                      ),
                      TextField(
                        key: const ValueKey('candidate-text'),
                        controller: _text,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 128000,
                        decoration: InputDecoration(
                          labelText: '候选正文',
                          hintText: '在此粘贴或整理正文，不会自动填入整份回复',
                          errorText: _textProblem,
                          counterText: '${_text.text.length} / 128,000',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _rangeConfirmed,
                        onChanged:
                            (value) => setState(() {
                              _rangeConfirmed = value ?? false;
                              _revision++;
                              _prepared = null;
                              _disk = null;
                            }),
                        title: Text(
                          candidate.operation ==
                                  CandidateOperation.replaceSelection
                              ? '按发送时的原选区比较'
                              : '按章节末尾新增比较',
                        ),
                      ),
                      OutlinedButton(
                        onPressed:
                            _rangeConfirmed &&
                                    !_reviewing &&
                                    _text.text.trim().isNotEmpty &&
                                    _text.value.composing.isCollapsed
                                ? _reviewText
                                : null,
                        child: Text(_reviewing ? '正在核对…' : '核对并比较'),
                      ),
                      if (_disk != null)
                        Text(
                          _disk!.sha256 == null
                              ? '暂时无法读取磁盘章节，可继续只读对照。'
                              : _disk!.matchesSource
                              ? '磁盘正文与发送时正文一致（本次核对）。'
                              : '磁盘正文与发送时不同，请先核对未保存修改或外部编辑。',
                        ),
                      if (_prepared != null) const Text('以下比较使用你整理的正文，尚未写入原稿。'),
                    ],
                    const SizedBox(height: 16),
                    if (!_editing || _prepared != null) ...[
                      if (diff.prefix.isNotEmpty)
                        Text('前方未变化：${diff.prefix.length} 字符'),
                      _section(
                        context,
                        '原文变化段',
                        diff.removed.isEmpty ? '（无）' : diff.removed,
                        Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: 0.12),
                      ),
                      const SizedBox(height: 12),
                      _section(
                        context,
                        '候选变化段',
                        diff.added.isEmpty ? '（无）' : diff.added,
                        Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: 0.12),
                      ),
                      if (diff.suffix.isNotEmpty)
                        Text('后方未变化：${diff.suffix.length} 字符'),
                    ],
                    const SizedBox(height: 12),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('来源与版本'),
                      children: [
                        SelectableText(
                          '请求编号：${candidate.completion.requestId}\n'
                          '基础正文指纹：${candidate.baseSha256}\n'
                          '原回复指纹：${candidate.completion.outputSha256}\n'
                          '${_prepared == null ? '' : '整理后正文指纹：${_prepared!.textSha256}\n选区指纹：${_prepared!.selectionSha256}\n'}'
                          '${_disk?.sha256 == null ? '' : '本次磁盘指纹：${_disk!.sha256}\n'}'
                          '长度与偏移采用 UTF-16 计数。方向在打开时核对，此页不提供采纳授权。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    Text(
                      _editing
                          ? '整理内容仅在此窗口保留，关闭即丢弃；尚不支持采纳写回。'
                          : '此比较只在当前聊天期间保留；关闭不会改动正文。',
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Widget _section(
    BuildContext context,
    String label,
    String text,
    Color color,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(12),
        color: color,
        child: SelectableText(CandidateDifference.excerpt(text)),
      ),
    ],
  );
}
