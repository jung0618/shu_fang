import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_routes.dart';
import '../services/editor_request_lease.dart';
import '../store/editor_store.dart';

/// 主动交互评审面板
class ActiveReviewPanel extends ConsumerStatefulWidget {
  const ActiveReviewPanel({super.key});

  @override
  ConsumerState<ActiveReviewPanel> createState() => _ActiveReviewPanelState();
}

class _ActiveReviewPanelState extends ConsumerState<ActiveReviewPanel> {
  List<Map<String, dynamic>> _questions = [];
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      await apiClient.get(ApiRoutes.activeReviewPreferences);
      // 加载偏好设置（如果有）
    } catch (_) {
      // 加载失败不影响使用
    }
  }

  Future<void> _generateQuestions() async {
    final lease = EditorRequestLease(ref);
    final text = ref.read(editorTextProvider);
    final book = ref.read(currentBookProvider);
    final chapter = ref.read(currentChapterProvider);

    // D37 Phase 1-3: 后端要求 book + chapter_id + current_text 三必填
    if (book == null || chapter == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先打开一本书的章节')));
      return;
    }
    if (text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在编辑器中输入内容')));
      return;
    }

    setState(() => _generating = true);
    try {
      final res = await apiClient.post(
        ApiRoutes.activeReviewGenerate,
        body: {'book': book, 'chapter_id': chapter, 'current_text': text},
      );
      if (!lease.isCurrent) return;
      if (!res.ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '生成失败: ${res.message.isEmpty ? "未知错误" : res.message}',
              ),
            ),
          );
        }
        setState(() => _generating = false);
        return;
      }
      // D37 Phase 1-3: 后端 result 可能直接是 {"questions": [...]} 或 {"questions": ..., "dimensions": ...}
      final data = res.data ?? {};
      final list = (data['questions'] as List?) ?? [];
      setState(() {
        _questions = list.cast<Map<String, dynamic>>();
        _generating = false;
      });
    } catch (e) {
      if (!lease.isCurrent) return;
      setState(() => _generating = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('生成失败: $e')));
      }
    }
  }

  // D37 Phase 1-3: feedback 改 action + dimension (后端不接受 rating)
  // action: accept | ignore | mute_category
  Future<void> _submitFeedback(
    String questionId,
    String action,
    String dimension,
  ) async {
    try {
      await apiClient.post(
        ApiRoutes.activeReviewFeedback,
        body: {
          'question_id': questionId,
          'action': action,
          'dimension': dimension,
        },
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('主动审阅', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              ElevatedButton(
                onPressed: _generating ? null : _generateQuestions,
                child:
                    _generating
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Text('生成问题'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_questions.isEmpty && !_generating)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '点击"生成问题"，AI 将从读者视角提出关于当前文本的问题',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          // 问题列表
          Expanded(
            child: ListView.builder(
              itemCount: _questions.length,
              itemBuilder: (context, index) {
                final q = _questions[index];
                return _QuestionCard(
                  question: q,
                  onAction:
                      (action, dimension) =>
                          _submitFeedback(q['id'] ?? '', action, dimension),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatefulWidget {
  final Map<String, dynamic> question;
  // D37 Phase 1-3: 改为 (action, dimension), action: accept|ignore|mute_category
  final void Function(String action, String dimension) onAction;

  const _QuestionCard({required this.question, required this.onAction});

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  String? _selectedAction;

  @override
  Widget build(BuildContext context) {
    final text = widget.question['question'] as String? ?? '';
    final dimension = widget.question['dimension'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (dimension.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  dimension,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF7C3AED),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(text, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            // D37 Phase 1-3: 改为 accept/ignore/mute 三按钮 (后端 action+dimension 契约)
            Row(
              children: [
                _FeedbackButton(
                  label: '采纳',
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF2B8A3E),
                  selected: _selectedAction == 'accept',
                  onTap: () {
                    setState(() => _selectedAction = 'accept');
                    widget.onAction('accept', dimension);
                  },
                ),
                const SizedBox(width: 8),
                _FeedbackButton(
                  label: '忽略',
                  icon: Icons.cancel_outlined,
                  color: const Color(0xFF868E96),
                  selected: _selectedAction == 'ignore',
                  onTap: () {
                    setState(() => _selectedAction = 'ignore');
                    widget.onAction('ignore', dimension);
                  },
                ),
                const SizedBox(width: 8),
                _FeedbackButton(
                  label: '静默此类',
                  icon: Icons.do_not_disturb_on_outlined,
                  color: const Color(0xFFC92A2A),
                  selected: _selectedAction == 'mute_category',
                  onTap: () {
                    setState(() => _selectedAction = 'mute_category');
                    widget.onAction('mute_category', dimension);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _FeedbackButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          border: Border.all(
            color: selected ? color : Theme.of(context).dividerColor,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color:
                    selected
                        ? color
                        : Theme.of(context).textTheme.bodySmall?.color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
