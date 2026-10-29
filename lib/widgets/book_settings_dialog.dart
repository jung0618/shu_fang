import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';

/// 书籍设置对话框 (右键书籍进入)
///
/// 编辑书名 / 简介 / 书封 emoji, 确认后写回 `books/<bookId>/manifest.json`。
/// 返回: pop(true) 表示有修改需要刷新, pop(false) 表示取消。
class BookSettingsDialog extends ConsumerStatefulWidget {
  final String bookId;
  final String initialTitle;
  final String initialDescription;
  final String initialCoverEmoji;

  const BookSettingsDialog({
    super.key,
    required this.bookId,
    required this.initialTitle,
    required this.initialDescription,
    required this.initialCoverEmoji,
  });

  @override
  ConsumerState<BookSettingsDialog> createState() => _BookSettingsDialogState();
}

class _BookSettingsDialogState extends ConsumerState<BookSettingsDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late String _emoji;
  bool _saving = false;
  String? _error;

  /// 常用书封 emoji (~30 个)
  static const List<String> _emojis = [
    '📖', '📕', '📗', '📘', '📙', '📓', '📔', '📚',
    '✍️', '🗡️', '⚔️', '🛡️', '🏰', '👑', '🐉', '🔥',
    '💧', '⚡', '🌟', '🌙', '☀️', '🎭', '🎨', '🎵',
    '🍀', '🌹', '❄️', '⛰️', '🌊', '🕊️',
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descController = TextEditingController(text: widget.initialDescription);
    _emoji = widget.initialCoverEmoji;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '书名不能为空');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 读现有 manifest (不存在则空 Map), 修改三字段后写回
      final manifest = await localDataSource.readBookManifest(widget.bookId);
      manifest['title'] = title;
      manifest['desc'] = _descController.text.trim();
      manifest['coverEmoji'] = _emoji;
      // 同步 name 字段, 保持与 createBook 写入格式一致
      manifest['name'] = title;
      final ok = await localDataSource.writeBookManifest(widget.bookId, manifest);
      if (!ok) {
        setState(() {
          _error = '写入失败';
          _saving = false;
        });
        return;
      }
      // 刷新书籍列表缓存
      ref.invalidate(booksProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = '保存失败: $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.book_rounded, size: 20),
          SizedBox(width: 8),
          Text('书籍设置'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _titleController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '书名 (必填)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '简介 (可选)',
                    border: OutlineInputBorder(),
                    isDense: true,
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                Text('书封 emoji', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                _EmojiGrid(
                  emojis: _emojis,
                  selected: _emoji,
                  onSelect: (e) => setState(() => _emoji = e),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save, size: 14),
          label: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }
}

/// emoji 选择网格 (Wrap 布局, 点击高亮选中项)
class _EmojiGrid extends StatelessWidget {
  final List<String> emojis;
  final String selected;
  final ValueChanged<String> onSelect;

  const _EmojiGrid({
    required this.emojis,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: emojis.map((e) {
        final isSel = e == selected;
        return InkWell(
          onTap: () => onSelect(e),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSel
                  ? scheme.primaryContainer.withValues(alpha: 0.7)
                  : null,
              border: Border.all(
                color: isSel ? scheme.primary : scheme.outlineVariant,
                width: isSel ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(e, style: const TextStyle(fontSize: 20)),
          ),
        );
      }).toList(),
    );
  }
}
