// ============================================================
// 设定文件编辑对话框 (D37 Phase 2-2: P0-10 修复)
// ============================================================
// 提取自 pages/settings_page.dart 的 _SettingFileEditDialog (死代码复用)
// 与写作 IDE 同机制: TextField + .md 保存 + 编辑/预览切换
// 让 widgets/settings_files_page.dart 的 ListTile onTap 能直接调用
// ============================================================

import 'package:flutter/material.dart';

import '../store/local_data_source.dart';
import '../theme/colors.dart';
import '../theme/radius.dart';
import '../theme/spacing.dart';
import 'markdown_view.dart';

/// 设定文件编辑对话框 (公开, 供 SettingsFilesPage 等调用)
class SettingFileEditDialog extends StatefulWidget {
  final String bookId;
  final String fileName;
  final String initialContent;
  final Future<bool> Function(String content) onSave;

  const SettingFileEditDialog({
    super.key,
    required this.bookId,
    required this.fileName,
    required this.initialContent,
    required this.onSave,
  });

  @override
  State<SettingFileEditDialog> createState() => _SettingFileEditDialogState();
}

class _SettingFileEditDialogState extends State<SettingFileEditDialog> {
  late final TextEditingController _controller;
  bool _dirty = false;
  bool _saving = false;
  bool _previewMode = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _controller.addListener(() {
      if (!_dirty && _controller.text != widget.initialContent) {
        setState(() => _dirty = true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Dialog(
      backgroundColor: AppPalette.surface(b),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.lg)),
      child: Container(
        width: 720,
        height: 640,
        padding: const EdgeInsets.all(S.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题栏
            Row(
              children: [
                const Icon(Icons.edit_note_rounded, size: 20),
                const SizedBox(width: S.sm),
                Expanded(
                  child: Text(
                    widget.fileName,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_dirty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '未保存',
                      style: TextStyle(fontSize: 10, color: AppColors.warning),
                    ),
                  ),
                const SizedBox(width: S.sm),
                // 编辑/预览切换
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.edit_rounded, size: 14),
                      label: Text('编辑'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.visibility_rounded, size: 14),
                      label: Text('预览'),
                    ),
                  ],
                  selected: {_previewMode},
                  onSelectionChanged: (s) =>
                      setState(() => _previewMode = s.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: S.xs),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    if (_dirty) {
                      final ok = await _confirmDiscard();
                      if (!ok) return;
                    }
                    navigator.pop();
                  },
                ),
              ],
            ),
            const SizedBox(height: S.md),
            // 内容区
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppPalette.divider(b)),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: _previewMode
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(S.md),
                        child: MarkdownView(data: _controller.text),
                      )
                    : TextField(
                        controller: _controller,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.6,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(S.md),
                          hintText: '输入 Markdown 内容...',
                        ),
                      ),
              ),
            ),
            const SizedBox(height: S.md),
            // 状态 + 保存
            Row(
              children: [
                Text(
                  '${_controller.text.length} 字符',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textTertiary(b),
                      ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: S.sm),
                FilledButton.icon(
                  onPressed: _saving || !_dirty
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          setState(() => _saving = true);
                          final ok =
                              await widget.onSave(_controller.text);
                          if (!mounted) return;
                          setState(() {
                            _saving = false;
                            if (ok) _dirty = false;
                          });
                          if (ok) {
                            messenger.showSnackBar(
                              const SnackBar(content: Text('已保存')),
                            );
                          } else {
                            messenger.showSnackBar(
                              const SnackBar(content: Text('保存失败')),
                            );
                          }
                        },
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 16),
                  label: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃修改?'),
        content: const Text('当前有未保存的修改, 确定要关闭吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

/// 便捷入口: 读取设定文件 → 弹编辑对话框 → 保存
/// 用法: await showSettingFileEditDialog(context, bookId, fileName);
Future<void> showSettingFileEditDialog(
  BuildContext context,
  String bookId,
  String fileName,
) async {
  final content = await localDataSource.readSetting(bookId, fileName);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => SettingFileEditDialog(
      bookId: bookId,
      fileName: fileName,
      initialContent: content ?? '',
      onSave: (newContent) =>
          localDataSource.writeSetting(bookId, fileName, newContent),
    ),
  );
}
