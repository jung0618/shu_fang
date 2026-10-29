import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../components/app_components.dart' show ToolbarIconButton;
import '../store/workspace_store.dart';
import '../store/editor_store.dart';
import '../store/navigation_store.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';

// ============================================================
// 侧边导航栏 (子项目 A)
// ============================================================
// 浏览器式 back/forward + 6 页面直达图标 + 当前位置指示.
// 解决"窗口无法返回"问题. 常驻左侧 56px, 专注模式隐藏.
// ============================================================

/// 侧边导航栏
class NavRail extends ConsumerWidget {
  const NavRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    final nav = ref.watch(navigationControllerProvider);
    final current = nav.current;
    final canBack = nav.canBack;
    final canForward = nav.canForward;
    final focus = ref.watch(focusModeProvider);

    return Container(
      width: 56,
      decoration: BoxDecoration(
        color: AppPalette.surface(b),
        border: Border(
          right: BorderSide(color: AppPalette.divider(b), width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: S.sm),
          // 返回 / 前进
          ToolbarIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: '后退 (Alt+←)',
            enabled: canBack,
            size: 40,
            iconSize: 20,
            onPressed:
                () => ref.read(navigationControllerProvider.notifier).back(),
          ),
          ToolbarIconButton(
            icon: Icons.arrow_forward_rounded,
            tooltip: '前进 (Alt+→)',
            enabled: canForward,
            size: 40,
            iconSize: 20,
            onPressed:
                () => ref.read(navigationControllerProvider.notifier).forward(),
          ),
          Divider(
            height: 1,
            indent: S.sm,
            endIndent: S.sm,
            color: AppPalette.divider(b),
          ),
          const SizedBox(height: S.xs),
          // 6 页面直达
          for (final entry in _navEntries)
            ToolbarIconButton(
              icon: entry.icon,
              tooltip: entry.label,
              active: current == entry.route,
              size: 40,
              iconSize: 20,
              onPressed:
                  () => ref
                      .read(navigationControllerProvider.notifier)
                      .push(entry.route),
            ),
          const Spacer(),
          // 底部: 当前用户头像 + 登出
          _UserChip(brightness: b),
          const SizedBox(height: S.xs),
          // 专注模式
          ToolbarIconButton(
            icon:
                focus
                    ? Icons.fullscreen_exit_rounded
                    : Icons.center_focus_strong_rounded,
            tooltip: focus ? '退出专注模式' : '专注模式',
            active: focus,
            size: 40,
            iconSize: 20,
            onPressed:
                () => ref.read(focusModeProvider.notifier).state = !focus,
          ),
          const SizedBox(height: S.sm),
        ],
      ),
    );
  }
}

/// 导航条目定义
class _NavEntry {
  final AppRoute route;
  final IconData icon;
  final String label;
  const _NavEntry(this.route, this.icon, this.label);
}

// D26 #6/8/10 修复: NavRail 减为 4 项顶级路由
// - 审阅 → 项目页 Tab 5 (从顶级路由下降)
// - 预设(原工程) → 项目页 Tab 6 (与项目合并, 作家术语)
// - 灵感 → 主页 quick action (从侧边栏移除)
const _navEntries = <_NavEntry>[
  _NavEntry(AppRoute.home, Icons.home_rounded, '主页'),
  _NavEntry(AppRoute.editor, Icons.edit_note_rounded, '写作'),
  _NavEntry(AppRoute.project, Icons.library_books_rounded, '项目'),
  _NavEntry(AppRoute.settings, Icons.settings_outlined, '设置'),
];

// T-23: _NavIconButton 已移除, 统一用 ToolbarIconButton (size: 40, iconSize: 20)

// ============================================================
// Local workspace shortcut
// ============================================================

/// Open the workspace chooser after saving drafts.
class _UserChip extends ConsumerWidget {
  final Brightness brightness;
  const _UserChip({required this.brightness});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentWorkspaceProvider);
    if (user == null) return const SizedBox.shrink();

    final initial = user.name.isNotEmpty ? user.name.characters.first : '书';

    return Tooltip(
      message: '${user.name}\n切换工作区（先保存草稿）',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap:
            ref.watch(workspaceControllerProvider).isLoading
                ? null
                : () => _switchWorkspace(context, ref),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color:
                user.isPrimary
                    ? AppColors.primaryContainer
                    : AppPalette.surfaceHigh(brightness),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  user.isPrimary
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : AppPalette.border(brightness),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color:
                    user.isPrimary
                        ? AppColors.onPrimaryContainer
                        : AppPalette.textPrimary(brightness),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _switchWorkspace(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(workspaceControllerProvider.notifier);
    final ok = await controller.leave();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(controller.error ?? '工作区未切换')));
    }
  }
}
