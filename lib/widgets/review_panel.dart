import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_routes.dart';
import '../services/editor_request_lease.dart';
import '../store/editor_store.dart';

// ============================================================
// 段落审阅 + 跨章节审阅面板 (D37 Phase 1-1/1-2 契约对齐)
// ============================================================
// 后端契约 (engine/api/review.py):
//   POST /api/review/paragraph      body: {text, model?}     返回 JSON: {violations, count, review}
//   POST /api/review/cross-chapter  body: {book, chapter_ids, model?}  返回 SSE 流:
//      data: {"type":"content","content":"chunk"}
//      data: {"type":"reasoning","reasoning":"..."}
//      data: {"type":"error_api","message":"..."}
//      data: [DONE]
// ============================================================

/// 段落审阅 + 跨章节审阅面板
class ReviewPanel extends ConsumerStatefulWidget {
  final String mode;

  const ReviewPanel({super.key, this.mode = 'paragraph'});

  @override
  ConsumerState<ReviewPanel> createState() => _ReviewPanelState();
}

class _ReviewPanelState extends ConsumerState<ReviewPanel> {
  Map<String, dynamic>? _result; // paragraph 模式结果
  String _streamedContent = ''; // cross-chapter 流式内容
  String _streamedReasoning = ''; // V4 推理内容
  String? _error;
  bool _reviewing = false;

  bool get _isCrossChapter => widget.mode == 'cross-chapter';

  @override
  Widget build(BuildContext context) {
    final title = _isCrossChapter ? '跨章节审阅' : '段落审阅';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _reviewing ? null : _review,
            child:
                _reviewing
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('开始审阅'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _buildErrorCard(_error!),
          ],
          if (_isCrossChapter && _streamedContent.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildStreamResult(),
          ] else if (!_isCrossChapter && _result != null) ...[
            const SizedBox(height: 16),
            _buildParagraphResult(),
          ],
        ],
      ),
    );
  }

  /// D37 Phase 1-1: 段落审阅 — 字段对齐 (前端发 text, 后端返 violations/count/review)
  Widget _buildParagraphResult() {
    // D37 Phase 0-5: error 键渲染为错误态卡片
    final errMsg = _result?['error'] as String?;
    if (errMsg != null) {
      return _buildErrorCard(errMsg);
    }
    final violations = _result?['violations'] as List? ?? [];
    final count = _result?['count'] as int? ?? violations.length;
    final reviewText = _result?['review'] as String? ?? '';

    return Expanded(
      child: ListView(
        children: [
          // 概要
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.flag_outlined,
                    size: 18,
                    color:
                        count > 0
                            ? const Color(0xFFC92A2A)
                            : const Color(0xFF2B8A3E),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '发现 $count 处问题',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ),
          // AI 评审文本 (review 字段)
          if (reviewText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 评审',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      reviewText,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
          // 违规列表 (violations 字段)
          if (violations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('违规明细', style: Theme.of(context).textTheme.titleSmall),
            ...violations.map((v) {
              final m = v is Map<String, dynamic> ? v : <String, dynamic>{};
              final rule = m['rule']?.toString() ?? m['type']?.toString() ?? '';
              final msg =
                  m['message']?.toString() ??
                  m['description']?.toString() ??
                  v.toString();
              return ListTile(
                leading: const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: Color(0xFFF59F00),
                ),
                title: Text(msg, style: Theme.of(context).textTheme.bodySmall),
                subtitle:
                    rule.isNotEmpty
                        ? Text(rule, style: const TextStyle(fontSize: 11))
                        : null,
                dense: true,
              );
            }),
          ],
        ],
      ),
    );
  }

  /// D37 Phase 1-2: 跨章审阅 — SSE 流式渲染
  Widget _buildStreamResult() {
    return Expanded(
      child: ListView(
        children: [
          if (_streamedReasoning.isNotEmpty) ...[
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 8),
              title: Row(
                children: [
                  const Icon(Icons.psychology_outlined, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '推理过程 (${_streamedReasoning.length} 字)',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              initiallyExpanded: false,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _streamedReasoning,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('审阅结果', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  SelectableText(
                    _streamedContent,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFC92A2A).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFC92A2A).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: Color(0xFFC92A2A)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '审阅失败',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFFC92A2A),
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  msg,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _review() async {
    final lease = EditorRequestLease(ref);
    final book = ref.read(currentBookProvider);
    final chapter = ref.read(currentChapterProvider);
    final text = ref.read(editorTextProvider);

    setState(() {
      _reviewing = true;
      _error = null;
      _result = null;
      _streamedContent = '';
      _streamedReasoning = '';
    });

    try {
      if (!_isCrossChapter) {
        // D37 Phase 1-1: 段落审阅 — 字段对齐 (text, 不再发 content/book/chapter_id)
        final res = await apiClient.post(
          ApiRoutes.reviewParagraph,
          body: {'text': text},
        );
        if (!lease.isCurrent) return;
        if (!res.ok) {
          setState(
            () =>
                _error =
                    res.message.isEmpty
                        ? '审阅失败 (code=${res.code})'
                        : res.message,
          );
        } else {
          setState(() => _result = res.data);
        }
      } else {
        // D37 Phase 1-2: 跨章审阅 — 改用 ssePostEvents 流式接收
        if (book == null) {
          setState(() => _error = '请先选择一本书');
          return;
        }
        final stream = apiClient.ssePostEvents(
          ApiRoutes.reviewCrossChapter,
          body: {
            'book': book,
            'chapter_ids': chapter == null ? <String>[] : [chapter],
          },
        );
        await for (final evt in stream) {
          if (!lease.isCurrent) return;
          if (evt.type == SseEventType.content) {
            setState(() => _streamedContent += evt.content);
          } else if (evt.type == SseEventType.reasoning) {
            setState(() => _streamedReasoning += evt.content);
          } else if (evt.type == SseEventType.error) {
            setState(() => _error = evt.content.isEmpty ? '引擎错误' : evt.content);
            break;
          } else if (evt.type == SseEventType.done) {
            break;
          }
        }
      }
    } catch (e) {
      if (lease.isCurrent) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }
}
