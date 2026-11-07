import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_routes.dart';
import '../services/editor_request_lease.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';
import '../theme/app_background.dart';

/// 灵感生成页面
class InspirePage extends ConsumerStatefulWidget {
  const InspirePage({super.key});

  @override
  ConsumerState<InspirePage> createState() => _InspirePageState();
}

class _InspirePageState extends ConsumerState<InspirePage> {
  final TextEditingController _promptController = TextEditingController();
  String _result = '';
  String _reasoning = ''; // T-7: V4 推理内容 (CoT, 与 _result 互斥显示)
  bool _generating = false;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final lease = EditorRequestLease(ref);
    try {
      final res = await apiClient.get(ApiRoutes.inspireHistory);
      if (!lease.isCurrent) return;
      final list = (res.data?['history'] as List?) ?? [];
      setState(() {
        _history = list.cast<Map<String, dynamic>>();
      });
    } catch (_) {}
  }

  Future<void> _generate() async {
    final lease = EditorRequestLease(ref);
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _generating = true;
      _result = '';
      _reasoning = '';
    });

    try {
      // T-1: 字段对齐 — 后端 inspire.py 读 `idea`, 不是 `prompt`
      // T-10: 传 book/chapter_id 让后端自动注入 lore context + 训练约束
      final bookId = ref.read(currentBookProvider);
      final chapterId = ref.read(currentChapterProvider);

      final stream = apiClient.ssePostEvents(
        ApiRoutes.inspireGenerate,
        body: {
          'idea': prompt,
          'model': ref.read(selectedModelProvider),
          if (bookId != null) 'book': bookId,
          if (chapterId != null) 'chapter_id': chapterId,
        },
      );

      String accumulated = '';
      String reasoningAcc = '';
      await for (final evt in stream) {
        if (!lease.isCurrent) return;
        if (evt.type == SseEventType.content) {
          accumulated += evt.content;
          setState(() => _result = accumulated);
        } else if (evt.type == SseEventType.reasoning) {
          reasoningAcc += evt.content;
          setState(() => _reasoning = reasoningAcc);
        } else if (evt.type == SseEventType.error) {
          setState(() => _result = '生成失败: ${evt.content}');
          break;
        } else if (evt.type == SseEventType.done) {
          break;
        }
      }
    } catch (e) {
      if (lease.isCurrent) setState(() => _result = '生成失败: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// 将当前生成结果保存为设定文件
  Future<void> _saveAsSetting() async {
    final lease = EditorRequestLease(ref);
    final result = _result;
    final bookId = ref.read(currentBookProvider);
    if (bookId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先在首页选择一本书')));
      }
      return;
    }
    if (_result.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final defaultName = '灵感_$dateStr.md';

    final fileName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: defaultName);
        return AlertDialog(
          title: const Text('保存为设定'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '文件名',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(ctx, name);
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (fileName == null || !lease.isCurrent) return;
    final ok = await localDataSource.createSettingFile(
      bookId,
      fileName,
      result,
    );
    if (!lease.isCurrent) return;
    if (ok) {
      messenger.showSnackBar(SnackBar(content: Text('已保存到设定集: $fileName')));
    } else {
      messenger.showSnackBar(const SnackBar(content: Text('保存失败: 文件可能已存在')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        appBar: AppBar(title: const Text('灵感生成')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 输入区
              Text('提示词', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _promptController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: '描述你想要生成的灵感方向...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _generating ? null : _generate,
                child:
                    _generating
                        ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('生成中...'),
                          ],
                        )
                        : const Text('生成灵感'),
              ),
              // V4 推理过程 (CoT, 可折叠) — T-7
              if (_reasoning.isNotEmpty) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Row(
                    children: [
                      Icon(
                        Icons.psychology_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '推理过程 (${_reasoning.length} 字)',
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
                          _reasoning,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // 结果区
              if (_result.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text(
                      '生成结果',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        // T-2: 设置 pendingInsert, editor_page 会 watch 并插入到光标位置
                        ref.read(pendingInsertProvider.notifier).state =
                            _result;
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已请求插入到当前章节')),
                          );
                        }
                      },
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('插入到编辑器'),
                    ),
                    TextButton.icon(
                      onPressed: _saveAsSetting,
                      icon: const Icon(Icons.bookmark_outline, size: 16),
                      label: const Text('保存为设定'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _result,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
              ],
              // 历史记录
              if (_history.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('历史记录', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final item = _history[index];
                      final prompt = (item['prompt'] as String?) ?? '';
                      final result = item['result'] as String? ?? '';
                      final createdAt = item['created_at'] as String? ?? '';
                      // 漂移避让: 默认态显示 emoji + prompt 前 20 字, 悬停后向左漂移揭示完整信息
                      return Card(
                        child: SizedBox(
                          height: 88,
                          // Phase 3.5b: 移除 DriftReveal (DriftReveal 仅用于主页快速入口条)
                          // 灵感卡直接显示完整信息, 无悬停切换
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  prompt,
                                  style: Theme.of(context).textTheme.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  result.length > 100
                                      ? '${result.substring(0, 100)}…'
                                      : result,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  createdAt,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
