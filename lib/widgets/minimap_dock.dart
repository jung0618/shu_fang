// Minimap 停靠容器 — 固定右侧 60px, 含 × 关闭 + 右键"不在本书展示"
//
// 设计原则:
// - 固定停靠 (非浮层), 符合 [视觉·权重] (不与正文抢戏, 但稳定存在)
// - × 关闭: 仅会话级 (写入 showMinimapProvider=false)
// - 右键"不在本书展示": 持久级 (写入 manifest.hideMinimap=true)
// - 同时尊重 showMinimapProvider (会话级) 和 isMinimapHiddenForCurrentBookProvider (持久级)
// - T-20: AI 面板关闭时, 顶部显示 AI emoji 快捷按钮 (竖排), 合并 2 栏→1 栏
//         AI 面板打开时, MinimapDock 隐藏 (AI 面板已含功能按钮)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../store/book_manifest_provider.dart';
import '../store/editor_store.dart';
import '../theme/theme.dart';
import 'minimap.dart';

class MinimapDock extends ConsumerWidget {
  final String text;
  final ScrollController scrollController;

  const MinimapDock({
    super.key,
    required this.text,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    final showMinimap = ref.watch(showMinimapProvider);
    final hiddenForBook = ref.watch(isMinimapHiddenForCurrentBookProvider);

    // T-20: AI 面板打开时隐藏 MinimapDock (合并 2 栏→1 栏)
    final showAiPanel = ref.watch(showAiPanelProvider);
    if (showAiPanel || !showMinimap || hiddenForBook) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 60,
      decoration: BoxDecoration(
        color: AppPalette.surface(b),
        border: Border(
          left: BorderSide(color: AppPalette.divider(b), width: 1),
        ),
      ),
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          _showMinimapContextMenu(context, details.globalPosition, ref);
        },
        child: Column(
          children: [
            // T-20: 顶部 AI emoji 快捷按钮 (竖排) + × 关闭
            _AiShortcutBar(),
            // 分割线
            Divider(height: 1, thickness: 1, color: AppPalette.divider(b)),
            // Minimap 主体
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Minimap(
                  text: text,
                  scrollController: scrollController,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMinimapContextMenu(
    BuildContext context,
    Offset position,
    WidgetRef ref,
  ) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: const [
        PopupMenuItem(
          value: 'hide_for_book',
          child: Text('不在本书展示'),
        ),
        PopupMenuItem(
          value: 'hide_session',
          child: Text('关闭 (本次会话)'),
        ),
      ],
    ).then((value) async {
      if (value == 'hide_for_book') {
        await setMinimapHiddenForCurrentBook(ref, true);
      } else if (value == 'hide_session') {
        ref.read(showMinimapProvider.notifier).state = false;
      }
    });
  }
}

/// T-20: AI emoji 快捷按钮栏 (竖排, 顶部)
/// 点击 emoji: 打开 AI 面板 + 触发对应操作
class _AiShortcutBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // × 关闭 minimap (右上角)
        Align(
          alignment: Alignment.topRight,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, size: 14),
            tooltip: '关闭 Minimap (本次会话)',
            onPressed: () {
              ref.read(showMinimapProvider.notifier).state = false;
            },
            splashRadius: 10,
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            padding: const EdgeInsets.only(top: 2, right: 2),
            visualDensity: VisualDensity.compact,
          ),
        ),
        // 4 个 AI emoji 快捷按钮
        _AiEmojiButton(
          icon: Icons.edit_note_rounded,
          tooltip: '续写 (打开 AI 面板)',
          action: AiAction.continueWrite,
        ),
        _AiEmojiButton(
          icon: Icons.lightbulb_outline_rounded,
          tooltip: '建议 (打开 AI 面板)',
          action: AiAction.suggest,
        ),
        _AiEmojiButton(
          icon: Icons.summarize_rounded,
          tooltip: '总结 (打开 AI 面板)',
          action: AiAction.summary,
        ),
        _AiEmojiButton(
          icon: Icons.auto_fix_high_rounded,
          tooltip: '改写 (打开 AI 面板)',
          action: AiAction.rewrite,
        ),
      ],
    );
  }
}

/// T-20: 单个 AI emoji 按钮
class _AiEmojiButton extends ConsumerWidget {
  final IconData icon;
  final String tooltip;
  final AiAction action;

  const _AiEmojiButton({
    required this.icon,
    required this.tooltip,
    required this.action,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: () {
        // 打开 AI 面板 + 触发对应操作
        // D50-8: 写源 Provider 而非派生 Provider, 确保持久化生效
        ref.read(aiPanelExpandedProvider.notifier).state = true;
        startAiAction(ref, action);
      },
      splashRadius: 14,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
