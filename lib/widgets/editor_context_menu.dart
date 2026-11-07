// 编辑器右键菜单 — 含预设片段库 + 历史剪切板 (per-book 持久化)
//
// 设计:
// - 标准按钮行: 复制 / 剪切 / 粘贴 / 高亮颜色 (有选区时)
// - 预设片段库 (默认展示): 列出该书所有预设片段, 点击插入到光标, 长按编辑/删除
// - 历史剪切板 (点击展开): 折叠状态, 点击 header 展开列表, 每条点击插入, 单条可删除
// - 复制/剪切时自动记录到历史剪切板 (在 EditorContextMenu 中触发)
//
// 使用方式:
//   return AdaptiveTextSelectionToolbar(
//     anchors: editableTextState.contextMenuAnchors,
//     children: [EditorContextMenu(...)],
//   );

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../store/editor_store.dart' show HighlightColor;
import '../store/snippets_store.dart';
import '../widgets/highlighted_text_editing_controller.dart';

class EditorContextMenu extends ConsumerStatefulWidget {
  final EditableTextState editableTextState;
  final HighlightedTextEditingController controller;
  final String? bookId;

  /// 高亮按钮回调 (颜色 / 起点 / 终点 / 选中文本)
  final void Function(HighlightColor color, int start, int end, String selected)
      onHighlight;

  const EditorContextMenu({
    super.key,
    required this.editableTextState,
    required this.controller,
    required this.bookId,
    required this.onHighlight,
  });

  @override
  ConsumerState<EditorContextMenu> createState() => _EditorContextMenuState();
}

class _EditorContextMenuState extends ConsumerState<EditorContextMenu> {
  bool _historyExpanded = false;
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = widget.controller.value;
    final selection = value.selection;
    final hasSelection =
        selection.isValid && selection.start != selection.end;
    final bookId = widget.bookId;

    // 首次显示时加载片段库 + 历史 (loadSnippetsForBook 内部有防重)
    if (bookId != null && !_loaded) {
      _loaded = true;
      Future.microtask(() => loadSnippetsForBook(ref, bookId));
    }

    final snippets = bookId != null
        ? ref.watch(presetSnippetsProvider(bookId))
        : const <PresetSnippet>[];
    final history = bookId != null
        ? ref.watch(clipboardHistoryProvider(bookId))
        : const <ClipboardEntry>[];

    return Container(
      width: 320,
      constraints: const BoxConstraints(maxHeight: 420),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ===== 标准按钮行 (复制 / 剪切 / 粘贴 / 高亮) =====
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Wrap(
                children: [
                  _MenuButton(
                    label: '复制',
                    enabled: hasSelection,
                    onTap: () {
                      if (hasSelection && bookId != null) {
                        final sel = widget.controller.selection;
                        final text = widget.controller.text
                            .substring(sel.start, sel.end);
                        recordClipboardHistory(ref, bookId, text);
                      }
                      widget.editableTextState
                          .copySelection(SelectionChangedCause.toolbar);
                      widget.editableTextState.hideToolbar();
                    },
                  ),
                  _MenuButton(
                    label: '剪切',
                    enabled: hasSelection,
                    onTap: () {
                      if (hasSelection && bookId != null) {
                        final sel = widget.controller.selection;
                        final text = widget.controller.text
                            .substring(sel.start, sel.end);
                        recordClipboardHistory(ref, bookId, text);
                      }
                      widget.editableTextState
                          .cutSelection(SelectionChangedCause.toolbar);
                      widget.editableTextState.hideToolbar();
                    },
                  ),
                  _MenuButton(
                    label: '粘贴',
                    onTap: () {
                      widget.editableTextState
                          .pasteText(SelectionChangedCause.toolbar);
                      widget.editableTextState.hideToolbar();
                    },
                  ),
                  if (hasSelection)
                    for (int i = 0; i < HighlightColor.values.length; i++)
                      _MenuButton(
                        label: _highlightLabel(HighlightColor.values[i], i),
                        onTap: () {
                          widget.editableTextState.hideToolbar();
                          final sel = widget.controller.selection;
                          if (sel.isValid && sel.start != sel.end) {
                            final selected = widget.controller.text
                                .substring(sel.start, sel.end);
                            widget.onHighlight(
                              HighlightColor.values[i],
                              sel.start,
                              sel.end,
                              selected,
                            );
                          }
                        },
                      ),
                ],
              ),
            ),
            // ===== 预设片段库 (默认展示) =====
            if (bookId != null) ...[
              const Divider(height: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.bookmark_outline,
                        size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('预设片段 (${snippets.length})',
                        style: theme.textTheme.labelSmall),
                    const Spacer(),
                    InkWell(
                      onTap: () => _showAddSnippetDialog(bookId),
                      borderRadius: BorderRadius.circular(12),
                      child: Tooltip(
                        message: '添加片段',
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.add,
                              size: 16, color: theme.colorScheme.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (snippets.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  child: Text(
                    '暂无预设片段, 点 + 添加 (或选中文本后右键自动填充)',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.disabledColor),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Wrap(
                    children: [
                      for (final s in snippets)
                        _SnippetChip(
                          title: s.title,
                          preview: s.content,
                          onTap: () => _insertText(s.content),
                          onLongPress: () =>
                              _showSnippetActions(bookId, s),
                        ),
                    ],
                  ),
                ),
              // ===== 历史剪切板 (点击展开) =====
              const Divider(height: 1),
              InkWell(
                onTap: () =>
                    setState(() => _historyExpanded = !_historyExpanded),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.history,
                          size: 14, color: theme.colorScheme.secondary),
                      const SizedBox(width: 6),
                      Text('历史剪切板 (${history.length})',
                          style: theme.textTheme.labelSmall),
                      const Spacer(),
                      Icon(
                        _historyExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              if (_historyExpanded)
                if (history.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: Text(
                      '暂无历史 (复制/剪切时自动记录, 最多保留 50 条)',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.disabledColor),
                    ),
                  )
                else ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      children: [
                        for (final e in history)
                          ListTile(
                            dense: true,
                            title: Text(
                              e.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                            trailing: InkWell(
                              onTap: () =>
                                  removeClipboardEntry(ref, bookId, e.id),
                              borderRadius: BorderRadius.circular(12),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close, size: 14),
                              ),
                            ),
                            onTap: () => _insertText(e.content),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => clearClipboardHistory(ref, bookId),
                        icon: const Icon(Icons.delete_outline, size: 14),
                        label: const Text('清空',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
                ],
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  String _highlightLabel(HighlightColor c, int index) {
    final emoji = switch (c) {
      HighlightColor.yellow => '🟡',
      HighlightColor.red => '🔴',
      HighlightColor.blue => '🔵',
      HighlightColor.green => '🟢',
      HighlightColor.purple => '🟣',
    };
    final shortcut = index < 3 ? ' (Ctrl+${index + 1})' : '';
    return '$emoji ${c.label}$shortcut';
  }

  /// 把文本插入到光标位置 (或末尾), 然后关闭菜单
  void _insertText(String text) {
    final ctrl = widget.controller;
    final sel = ctrl.selection;
    final insertPos = sel.isValid ? sel.end : ctrl.text.length;
    final newText = ctrl.text.substring(0, insertPos) +
        text +
        ctrl.text.substring(insertPos);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: insertPos + text.length),
    );
    widget.editableTextState.hideToolbar();
    // 同步到全局 editorTextProvider (让字数统计/自动保存感知)
    // 注意: 这里改了 controller, onChanged 会被 TextField 触发, editorTextProvider 会自动更新
  }

  Future<void> _showAddSnippetDialog(String bookId) async {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    // 有选中文本则预填到 content
    final sel = widget.controller.selection;
    if (sel.isValid && sel.start != sel.end) {
      contentCtrl.text =
          widget.controller.text.substring(sel.start, sel.end);
    }
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加预设片段'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '标题',
                  hintText: '如: 风景描写 / 人物出场',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '内容',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final title = titleCtrl.text.trim();
              final content = contentCtrl.text;
              if (content.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('内容不能为空')),
                );
                return;
              }
              await addPresetSnippet(ref, bookId, title, content);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSnippetActions(
    String bookId, PresetSnippet snippet,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                snippet.title,
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
    if (action == 'edit') {
      await _showEditSnippetDialog(bookId, snippet);
    } else if (action == 'delete') {
      await removePresetSnippet(ref, bookId, snippet.id);
    }
  }

  Future<void> _showEditSnippetDialog(
    String bookId, PresetSnippet snippet,
  ) async {
    final titleCtrl = TextEditingController(text: snippet.title);
    final contentCtrl = TextEditingController(text: snippet.content);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑预设片段'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '内容',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final title = titleCtrl.text.trim();
              final content = contentCtrl.text;
              if (content.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('内容不能为空')),
                );
                return;
              }
              await updatePresetSnippet(
                ref, bookId, snippet.id, title, content,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

/// 菜单按钮 — 单击触发
class _MenuButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  const _MenuButton({required this.label, this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: enabled ? null : theme.disabledColor,
          ),
        ),
      ),
    );
  }
}

/// 预设片段 chip — 单击插入, 长按编辑/删除
class _SnippetChip extends StatelessWidget {
  final String title;
  final String preview;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _SnippetChip({
    required this.title,
    required this.preview,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 4),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Tooltip(
          message: preview.length > 80
              ? '${preview.substring(0, 80)}…'
              : preview,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              title,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
        ),
      ),
    );
  }
}
