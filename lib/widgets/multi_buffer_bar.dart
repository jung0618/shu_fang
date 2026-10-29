/// 多 Buffer Tab Bar — 顶部章节切换条
///
/// 显示所有打开的章节为 Tab，支持：
/// - 单击切换
/// - 中键 / × 关闭
/// - T-21: 拖拽重排 (ReorderableListView)
///
/// **设计**: 类似 VSCode / IntelliJ 的 Editor Tabs
/// **D26 修复**: 移除"关闭其他"按钮 (#3 用户反馈: 交互多余)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../store/editor_store.dart';
import '../services/chapter_save_queue.dart' show ChapterAddress;
import '../theme/colors.dart';
import '../theme/spacing.dart';

class MultiBufferBar extends ConsumerWidget {
  const MultiBufferBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buffers = ref.watch(openBuffersProvider);
    final queue = ref.watch(chapterSaveQueueProvider);
    final root = ref.watch(storageRootProvider);
    final activeIdx = ref.watch(activeBufferIndexProvider);
    final splitChapter = ref.watch(splitChapterProvider);
    if (buffers.isEmpty) {
      return const SizedBox.shrink();
    }
    final b = Theme.of(context).brightness;
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppPalette.surface(b),
        border: Border(
          bottom: BorderSide(color: AppPalette.divider(b), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            // T-21: ReorderableListView 替换 ListView.builder, 支持拖拽重排
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: buffers.length,
              buildDefaultDragHandles: false,
              onReorder:
                  (oldIndex, newIndex) =>
                      BufferActions.reorder(ref, oldIndex, newIndex),
              itemBuilder: (context, i) {
                return ReorderableDragStartListener(
                  key: ValueKey(buffers[i].key),
                  index: i,
                  child: _BufferTab(
                    buffer: buffers[i].copyWith(
                      isDirty: switch (queue.statusFor(
                        ChapterAddress(
                          root,
                          buffers[i].bookId,
                          buffers[i].chapterId,
                        ),
                      )) {
                        SaveStatus.idle || SaveStatus.saved => false,
                        _ => true,
                      },
                    ),
                    active: i == activeIdx,
                    isSplit: buffers[i].chapterId == splitChapter,
                    onTap: () => BufferActions.activate(ref, i),
                    onClose: () {
                      // 关闭的 tab 正好是分屏章 → 清除分屏状态
                      if (buffers[i].chapterId == splitChapter) {
                        ref.read(splitChapterProvider.notifier).state = null;
                      }
                      BufferActions.close(ref, i);
                    },
                    onToggleSplit: () {
                      if (buffers[i].chapterId == splitChapter) {
                        ref.read(splitChapterProvider.notifier).state = null;
                      } else {
                        ref.read(splitChapterProvider.notifier).state =
                            buffers[i].chapterId;
                      }
                    },
                  ),
                );
              },
            ),
          ),
          // 关闭其他按钮 (仅当 buffers > 1)
          if (buffers.length > 1)
            IconButton(
              tooltip: '关闭其他',
              icon: const Icon(Icons.clear_all, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                // 关闭其他后只留激活 tab, 若分屏章不在其中 → 清除分屏
                if (activeIdx >= 0 &&
                    activeIdx < buffers.length &&
                    buffers[activeIdx].chapterId != splitChapter) {
                  ref.read(splitChapterProvider.notifier).state = null;
                }
                BufferActions.closeOthers(ref);
              },
            ),
          const SizedBox(width: S.xs),
        ],
      ),
    );
  }
}

class _BufferTab extends StatelessWidget {
  final ChapterBuffer buffer;
  final bool active;
  final bool isSplit;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onToggleSplit;

  const _BufferTab({
    required this.buffer,
    required this.active,
    required this.isSplit,
    required this.onTap,
    required this.onClose,
    required this.onToggleSplit,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      onSecondaryTap: () => _showContextMenu(context),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200, minWidth: 80),
        padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: 4),
        margin: const EdgeInsets.only(right: 1),
        decoration: BoxDecoration(
          color:
              active
                  ? AppPalette.surfaceHigh(b)
                  : AppPalette.surface(b).withValues(alpha: 0.7),
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 章节序号图标 (分屏章用分屏图标)
            Icon(
              isSplit ? Icons.vertical_split_rounded : Icons.article_outlined,
              size: 14,
              color:
                  isSplit
                      ? AppColors.ai
                      : (active
                          ? AppColors.primary
                          : AppPalette.textTertiary(b)),
            ),
            const SizedBox(width: 4),
            // 标题
            Flexible(
              child: Text(
                _displayTitle(buffer),
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      active
                          ? AppPalette.textPrimary(b)
                          : AppPalette.textSecondary(b),
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            // 修改标记
            if (buffer.isDirty)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 2),
                decoration: const BoxDecoration(
                  color: AppColors.warning,
                  shape: BoxShape.circle,
                ),
              ),
            // 关闭按钮
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: AppPalette.textTertiary(b),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _displayTitle(ChapterBuffer b) {
    return b.title ?? b.chapterId;
  }

  void _showContextMenu(BuildContext context) async {
    final b = Theme.of(context).brightness;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final pos = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(box.size.topLeft(Offset.zero), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<String>(
      context: context,
      position: pos,
      items: [
        PopupMenuItem(
          value: 'toggleSplit',
          child: Row(
            children: [
              Icon(
                isSplit ? Icons.close_fullscreen : Icons.vertical_split_rounded,
                size: 14,
                color: AppPalette.textSecondary(b),
              ),
              const SizedBox(width: 8),
              Text(isSplit ? '取消分屏' : '分屏打开'),
            ],
          ),
        ),
        const PopupMenuItem(value: 'close', child: Text('关闭')),
        // D26 修复: 移除"关闭其他"右键菜单项 (#3 用户反馈: 交互多余)
      ],
    );
    if (selected == 'toggleSplit') onToggleSplit();
    if (selected == 'close') onClose();
  }
}
