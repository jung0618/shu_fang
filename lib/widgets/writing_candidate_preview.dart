import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/writing_candidate.dart';
import '../store/editor_store.dart';

/// No write, clipboard, model, preference or training action exists here.
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

  @override
  void initState() {
    super.initState();
    _checkDirection();
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
                    !identical(handle?.controller, widget.origin.controller)
                ? '章节或编辑器已切换；旧比较已隐藏。'
                : _directionProblem);
        final diff = candidate.difference;
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
                    const Text('整份回复作为比较内容，可能包含模型说明；未自动提取正文。多处变化合并显示。'),
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 12),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('来源与版本'),
                      children: [
                        SelectableText(
                          '请求编号：${candidate.completion.requestId}\n'
                          '基础正文指纹：${candidate.baseSha256}\n'
                          '候选指纹：${candidate.completion.outputSha256}\n'
                          '长度与偏移采用 UTF-16 计数。方向在打开时核对，此页不提供采纳授权。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const Text('此比较只在当前聊天期间保留；关闭不会改动正文。'),
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
