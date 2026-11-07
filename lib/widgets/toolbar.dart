import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/flavor.dart';
import '../store/editor_store.dart';
import '../theme/theme.dart';
import '../widgets/search_dialog.dart';
import '../widgets/finalize_dialog.dart';
import '../widgets/incremental_index_dialog.dart';
import '../widgets/chapter_recovery_dialog.dart';
import '../widgets/export_panel.dart';
import 'writing_practice_history_dialog.dart';
import 'writing_request_history_dialog.dart';
import '../store/local_data_source.dart';

/// 顶部工具条 (D23: 真实撤销/重做 + 移除占位路由, 页面导航统一走 NavRail)
class Toolbar extends ConsumerWidget {
  const Toolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    final saveStatus = ref.watch(saveStatusProvider);
    final book = ref.watch(currentBookProvider);
    final chapter = ref.watch(currentChapterProvider);
    final focus = ref.watch(focusModeProvider);
    final font = ref.watch(editorFontFamilyProvider);
    final undoCtrl = ref.watch(editorUndoControllerProvider);
    final chapterReady =
        book != null &&
        chapter != null &&
        undoCtrl != null &&
        ref.watch(chapterContentProvider('$book:$chapter')).hasValue;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: S.md),
      decoration: BoxDecoration(
        color: AppPalette.surface(b),
        border: Border(
          bottom: BorderSide(color: AppPalette.divider(b), width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Keep the fixed-height toolbar usable when the window is narrow or
          // the system text scale is larger. The less frequent actions live in
          // the overflow menu so the primary editing controls keep their space.
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final compact = constraints.maxWidth < 760 || textScale > 1.15;
          return Row(
            children: [
              // Logo
              _Logo(showLabel: !compact),
              const SizedBox(width: S.lg),
              // 分隔
              Container(width: 1, height: 20, color: AppPalette.divider(b)),
              const SizedBox(width: S.md),
              // 撤销/重做 (D23: 真实调用 UndoHistoryController)
              // D50: controller 可能为 null (无获焦编辑器), 按钮禁用
              ToolbarIconButton(
                icon: Icons.undo_rounded,
                tooltip: '撤销 (Ctrl+Z)',
                onPressed: undoCtrl == null ? null : () => undoCtrl.undo(),
              ),
              ToolbarIconButton(
                icon: Icons.redo_rounded,
                tooltip: '重做 (Ctrl+Y)',
                onPressed: undoCtrl == null ? null : () => undoCtrl.redo(),
              ),
              const ToolbarDivider(),
              // 字体切换
              _FontMenu(
                current: font,
                onChanged: (v) {
                  ref.read(editorFontFamilyProvider.notifier).state = v;
                },
              ),
              // 专注模式
              ToolbarIconButton(
                icon:
                    focus
                        ? Icons.fullscreen_exit_rounded
                        : Icons.center_focus_strong_rounded,
                tooltip: focus ? '退出专注模式' : '专注模式',
                active: focus,
                onPressed:
                    () => ref.read(focusModeProvider.notifier).state = !focus,
              ),
              const ToolbarDivider(),
              // 跨章搜索
              ToolbarIconButton(
                icon: Icons.search_rounded,
                tooltip: '跨章搜索 (Ctrl+Shift+F)',
                onPressed:
                    () => showDialog(
                      context: context,
                      builder: (_) => const SearchDialog(),
                    ),
              ),
              const Spacer(),
              PopupMenuButton<_ToolbarAction>(
                tooltip: '更多操作',
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (action) async {
                  switch (action) {
                    case _ToolbarAction.requestHistory:
                      await showDialog<void>(
                        context: context,
                        builder:
                            (_) => WritingRequestHistoryDialog(
                              root: localDataSource.storageRoot,
                            ),
                      );
                      return;
                    case _ToolbarAction.practiceHistory:
                      showWritingPracticeHistory(context, ref);
                      return;
                    case _ToolbarAction.recovery:
                      final restored = await showDialog<bool>(
                        context: context,
                        builder: (_) => const ChapterRecoveryDialog(),
                      );
                      if (context.mounted && restored == true) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('已载入上一版，正在按正常流程保存。请留意保存状态。'),
                          ),
                        );
                      }
                      return;
                    case _ToolbarAction.export:
                      await showDialog<void>(
                        context: context,
                        builder:
                            (context) => Dialog(
                              child: SizedBox(
                                width: 560,
                                height:
                                    MediaQuery.sizeOf(context).height * 0.72,
                                child: Column(
                                  children: [
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: IconButton(
                                        tooltip: '关闭',
                                        onPressed:
                                            () => Navigator.of(context).pop(),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ),
                                    const Expanded(child: ExportPanel()),
                                  ],
                                ),
                              ),
                            ),
                      );
                      return;
                    case _ToolbarAction.incrementalIndex:
                      await showDialog(
                        context: context,
                        builder: (_) => const IncrementalIndexDialog(),
                      );
                      return;
                    case _ToolbarAction.finalize:
                      await showDialog(
                        context: context,
                        builder:
                            (_) =>
                                FinalizeDialog(book: book!, chapter: chapter!),
                      );
                      return;
                  }
                },
                itemBuilder:
                    (_) => [
                      PopupMenuItem(
                        value: _ToolbarAction.requestHistory,
                        enabled: localDataSource.hasWorkspace,
                        child: const _ToolbarMenuLabel(
                          icon: Icons.receipt_long_outlined,
                          label: '写作调用记录',
                        ),
                      ),
                      PopupMenuItem(
                        value: _ToolbarAction.practiceHistory,
                        enabled: book != null,
                        child: const _ToolbarMenuLabel(
                          icon: Icons.history_edu,
                          label: '练习记录与作品偏好',
                        ),
                      ),
                      PopupMenuItem(
                        value: _ToolbarAction.recovery,
                        enabled: chapterReady,
                        child: const _ToolbarMenuLabel(
                          icon: Icons.history_rounded,
                          label: '查看／恢复上一版',
                        ),
                      ),
                      PopupMenuItem(
                        value: _ToolbarAction.export,
                        enabled: book != null,
                        child: const _ToolbarMenuLabel(
                          icon: Icons.file_download_outlined,
                          label: '导出作品',
                        ),
                      ),
                      const PopupMenuItem(
                        value: _ToolbarAction.incrementalIndex,
                        child: _ToolbarMenuLabel(
                          icon: Icons.refresh_rounded,
                          label: '增量更新索引',
                        ),
                      ),
                      PopupMenuItem(
                        value: _ToolbarAction.finalize,
                        enabled: book != null && chapter != null,
                        child: const _ToolbarMenuLabel(
                          icon: Icons.task_alt_rounded,
                          label: '定档',
                        ),
                      ),
                    ],
              ),
              const ToolbarDivider(),
              // 保存状态
              _SaveStatusIndicator(status: saveStatus),
              const SizedBox(width: S.sm),
            ],
          );
        },
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final bool showLabel;
  const _Logo({this.showLabel = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.aiGradientStart, AppColors.aiGradientEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: const Icon(
            Icons.menu_book_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: S.sm),
          Text(kShuFangBrand, style: Theme.of(context).textTheme.titleLarge),
        ],
      ],
    );
  }
}

enum _ToolbarAction {
  requestHistory,
  recovery,
  export,
  incrementalIndex,
  finalize,
  practiceHistory,
}

class _ToolbarMenuLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ToolbarMenuLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: S.sm),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}

class _SaveStatusIndicator extends StatelessWidget {
  final SaveStatus status;
  const _SaveStatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final (icon, text, color) = switch (status) {
      SaveStatus.idle => (
        Icons.check_circle_outline_rounded,
        '就绪',
        AppPalette.disabled(b),
      ),
      SaveStatus.unsaved => (
        Icons.edit_outlined,
        '待保存',
        Theme.of(context).colorScheme.primary,
      ),
      SaveStatus.saving => (
        Icons.sync_rounded,
        '保存中…',
        Theme.of(context).colorScheme.primary,
      ),
      SaveStatus.saved => (
        Icons.check_circle_rounded,
        '已保存',
        AppColors.success,
      ),
      SaveStatus.error => (
        Icons.error_outline_rounded,
        '保存失败',
        AppColors.error,
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: S.xs),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _FontMenu extends StatelessWidget {
  final String? current;
  final ValueChanged<String?> onChanged;
  const _FontMenu({required this.current, required this.onChanged});

  // A null menu result means dismissal in Flutter, so use a non-null value
  // for the default font and translate it back only after selection.
  static const Map<String, String> _options = {
    '': '默认',
    'serif': '宋体',
    'sans-serif': '黑体',
    'monospace': '等宽',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '字体',
      icon: const Icon(Icons.text_fields_rounded, size: 16),
      initialValue: current ?? '',
      onSelected: (value) => onChanged(value.isEmpty ? null : value),
      position: PopupMenuPosition.under,
      itemBuilder:
          (ctx) =>
              _options.entries
                  .map(
                    (e) => PopupMenuItem<String>(
                      value: e.key,
                      child: Text(
                        e.value,
                        style: TextStyle(
                          fontFamily: e.key.isEmpty ? null : e.key,
                        ),
                      ),
                    ),
                  )
                  .toList(),
    );
  }
}
