import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_routes.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';

/// AI 大纲管理组件
class OutlineGenerator extends ConsumerStatefulWidget {
  final String? bookId;
  const OutlineGenerator({super.key, this.bookId});

  @override
  ConsumerState<OutlineGenerator> createState() => _OutlineGeneratorState();
}

class _OutlineGeneratorState extends ConsumerState<OutlineGenerator> {
  late final TextEditingController _controller;
  String? _bookId;
  bool _generating = false;
  bool _loading = false;
  bool _saving = false; // D37 Phase 0-2: 大纲保存进行中标志

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _bookId;
    if (id == null) return;
    setState(() => _loading = true);
    try {
      final res = await apiClient.get(ApiRoutes.outline(id));
      final content = res.data?['outline'] as String? ?? '';
      setState(() {
        _controller.text = content;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    final id = _bookId;
    if (id == null) return;

    // D37 Phase 1-6: 后端要求 book + chapter_ids (至少 1 个)
    // 简化方案: 弹一个章节选择对话框让用户勾选要纳入大纲生成的章节
    final currentChapter = ref.read(currentChapterProvider);
    final chapterIds = await _pickChapters(id, currentChapter);
    if (chapterIds == null || chapterIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需至少选择 1 个章节才能生成大纲')),
        );
      }
      return;
    }

    setState(() => _generating = true);
    try {
      final res = await apiClient.post(
        ApiRoutes.outlineGenerate,
        body: {
          'book': id,
          'chapter_ids': chapterIds,
        },
      );
      if (!mounted) return;
      if (!res.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('大纲生成失败: ${res.message.isEmpty ? "未知错误" : res.message}')),
        );
        return;
      }
      final content = res.data?['outline'] as String? ?? '';
      setState(() => _controller.text = content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('大纲生成失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// D37 Phase 1-6: 章节多选对话框 (供大纲生成使用)
  Future<List<String>?> _pickChapters(String bookId, String? preselect) async {
    try {
      // 用 LocalDataSource 列章节, 避免依赖引擎
      final chapters = await localDataSource.listChapters(bookId);
      if (chapters.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('本书暂无章节, 无法生成大纲')),
          );
        }
        return null;
      }
      final selected = <String>{if (preselect != null) preselect};
      if (!mounted) return null;
      return showDialog<List<String>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: const Text('选择纳入大纲生成的章节'),
            content: SizedBox(
              width: 400,
              child: ListView(
                shrinkWrap: true,
                children: chapters.map((c) {
                  final id = c.id;
                  return CheckboxListTile(
                    value: selected.contains(id),
                    onChanged: (v) {
                      setSt(() {
                        if (v == true) {
                          selected.add(id);
                        } else {
                          selected.remove(id);
                        }
                      });
                    },
                    title: Text(c.title.isEmpty ? id : c.title),
                    dense: true,
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, selected.toList()),
                child: Text('生成 (${selected.length})'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载章节失败: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _save() async {
    final id = _bookId;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      // D37 Phase 0-2: 后端 units.py:364 读 request.get_data(as_text=True) 裸文本
      // 不能发 JSON body, 必须用 putText 发 text/plain
      final res = await apiClient.putText(ApiRoutes.outline(id), _controller.text);
      if (!mounted) return;
      if (res.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('大纲已保存'), duration: Duration(seconds: 1)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: ${res.message.isEmpty ? "未知错误" : res.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentBook = ref.watch(currentBookProvider);
    _bookId = widget.bookId ?? currentBook;
    if (_bookId == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('请先选择一本书'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.list_alt, size: 20),
              const SizedBox(width: 8),
              Text('大纲管理', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('加载'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _generating ? null : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 16),
                label: const Text('AI 生成'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save, size: 16),
                label: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const LinearProgressIndicator()
          else
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  hintText: '在此输入或生成大纲...',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
