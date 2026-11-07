// 左侧固定 256px 章节树容器 — 含收起按钮, 收起后变为 4px hover 触发条
//
// 设计原则:
// - 固定左侧 (不悬浮), 符合 [视觉·连续] [导航·固定不藏]
// - 收起后留 4px 边条, hover 展开到 12px 提示, 点击恢复
// - 收起状态持久化到 user_prefs.json (跨会话记住)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../store/editor_store.dart' show sidebarCollapsedProvider;
import '../theme/theme.dart';
import 'sidebar_tree.dart';

class ChapterSidebar extends ConsumerWidget {
  const ChapterSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(sidebarCollapsedProvider);
    if (collapsed) return const _SidebarCollapsedEdge();

    return Container(
      width: 256,
      decoration: BoxDecoration(
        color: AppPalette.surface(Theme.of(context).brightness),
        border: Border(
          right: BorderSide(
            color: AppPalette.divider(Theme.of(context).brightness),
            width: 1,
          ),
        ),
      ),
      child: const SidebarTree(),
    );
  }
}

// 收起态: 4px hover 触发条, 不持续悬浮
class _SidebarCollapsedEdge extends ConsumerStatefulWidget {
  const _SidebarCollapsedEdge();

  @override
  ConsumerState<_SidebarCollapsedEdge> createState() =>
      _SidebarCollapsedEdgeState();
}

class _SidebarCollapsedEdgeState extends ConsumerState<_SidebarCollapsedEdge> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          ref.read(sidebarCollapsedProvider.notifier).state = false;
        },
        child: AnimatedContainer(
          duration: Motion.fast,
          width: _hovered ? 12 : 4,
          color: _hovered ? AppPalette.divider(b) : AppPalette.surface(b),
          child: _hovered
              ? const Center(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
