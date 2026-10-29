// =============================================================================
// ShuFang Design System — Reusable Components
// =============================================================================
// 统一的可复用 UI 组件。所有内部 widget 应该优先用这些组件。
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/elevation.dart';
import '../theme/radius.dart';
import '../theme/spacing.dart';

/// 应用顶部品牌条 — 用于引擎加载、空状态等场景。
class BrandHeader extends StatelessWidget {
  /// 副标题
  final String subtitle;

  /// 是否显示"私有版"徽标
  final bool showPrivateBadge;

  const BrandHeader({
    super.key,
    this.subtitle = '桌面写作 IDE',
    this.showPrivateBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.aiGradientStart, AppColors.aiGradientEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: const Icon(
            Icons.menu_book_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: S.md),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '书坊',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (showPrivateBadge) ...[
                  const SizedBox(width: S.sm),
                  _PrivateBadge(),
                ],
              ],
            ),
            Text(
              subtitle,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppPalette.textSecondary(b)),
            ),
          ],
        ),
      ],
    );
  }
}

class _PrivateBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.xs),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Text(
        '私有版',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.warning,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 通用空状态组件。
class EmptyState extends StatelessWidget {
  /// 图标
  final IconData icon;

  /// 标题
  final String title;

  /// 副标题（可选）
  final String? subtitle;

  /// 主 CTA 按钮文字
  final String? actionLabel;

  /// 主 CTA 回调
  final VoidCallback? onAction;

  /// 次 CTA 按钮文字
  final String? secondaryActionLabel;

  /// 次 CTA 回调
  final VoidCallback? onSecondaryAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(S.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppPalette.surfaceHigh(b),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppPalette.border(b),
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: AppPalette.textSecondary(b),
                ),
              ),
              const SizedBox(height: S.lg),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: S.sm),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppPalette.textSecondary(b),
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (actionLabel != null) ...[
                const SizedBox(height: S.xl),
                FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
              if (secondaryActionLabel != null) ...[
                const SizedBox(height: S.sm),
                TextButton(
                  onPressed: onSecondaryAction,
                  child: Text(secondaryActionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 通用错误状态。
class ErrorStateView extends StatelessWidget {
  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final IconData icon;

  const ErrorStateView({
    super.key,
    this.title = '出了点问题',
    this.message,
    this.onRetry,
    this.icon = Icons.error_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: icon,
      title: title,
      subtitle: message,
      actionLabel: onRetry != null ? '重试' : null,
      onAction: onRetry,
    );
  }
}

/// AI 渐变容器 — 用于 AI 主题徽标/按钮。
class AiGradientContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const AiGradientContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.radius = R.sm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.aiGradientStart, AppColors.aiGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 0.2,
        ),
        child: child,
      ),
    );
  }
}

/// 通用 Section 标题行（图标 + 标题 + 右侧操作）
class SectionHeader extends StatelessWidget {
  final IconData? icon;
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    this.icon,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(S.lg, S.md, S.md, S.sm),
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AppPalette.textSecondary(b)),
            const SizedBox(width: S.xs),
          ],
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 内联状态点 (绿/灰/红/黄)
class StatusDot extends StatelessWidget {
  final AppStatus status;
  final double size;

  const StatusDot({super.key, required this.status, this.size = 8});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      AppStatus.idle => AppPalette.disabled(Theme.of(context).brightness),
      AppStatus.success => AppColors.success,
      AppStatus.warning => AppColors.warning,
      AppStatus.error => AppColors.error,
      AppStatus.info => AppColors.info,
      AppStatus.ai => AppColors.ai,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: status == AppStatus.ai
            ? [
                BoxShadow(
                  color: AppColors.ai.withValues(alpha: 0.4),
                  blurRadius: size,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
    );
  }
}

enum AppStatus { idle, success, warning, error, info, ai }

/// 加载指示器（带文字）
class LoadingLine extends StatelessWidget {
  final String text;
  final double size;

  const LoadingLine({super.key, required this.text, this.size = 12});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: S.sm),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textSecondary(b),
              ),
        ),
      ],
    );
  }
}

/// 通用卡片容器 — 比 Card 更可控。
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  final bool elevated;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(S.lg),
    this.margin,
    this.onTap,
    this.color,
    this.radius = R.md,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final bg = color ?? AppPalette.surface(b);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppPalette.border(b), width: 1),
        boxShadow: elevated ? Elevation.shadowLow(b) : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// 分组标题（侧边栏内）— 比 SectionHeader 更紧凑。
class GroupLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const GroupLabel({super.key, required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.md, S.xs),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textTertiary(b),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 工具栏图标按钮 — 统一尺寸/反馈。
/// T-23: 扩展支持 size/iconSize/enabled/backgroundColor, 替代 _NavIconButton/_SmallIconButton
class ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final Color? activeColor;
  final double size;
  final double iconSize;
  final bool enabled;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;

  const ToolbarIconButton({
    super.key,
    required this.icon,
    this.tooltip,
    this.onPressed,
    this.active = false,
    this.activeColor,
    this.size = 32,
    this.iconSize = 16,
    this.enabled = true,
    this.backgroundColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final color = !enabled
        ? AppPalette.disabled(b)
        : active
            ? (activeColor ?? Theme.of(context).colorScheme.primary)
            : AppPalette.textSecondary(b);
    final bg = backgroundColor ??
        (active ? AppColors.primaryContainer.withValues(alpha: 0.6) : null);
    final radius = borderRadius ?? BorderRadius.circular(8);

    // 有背景色时用 InkWell 容器 (类似 _NavIconButton), 否则用标准 IconButton (向后兼容)
    if (bg != null) {
      return Tooltip(
        message: tooltip ?? '',
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: radius,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
            ),
            child: Icon(icon, size: iconSize, color: color),
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        icon: Icon(icon, size: iconSize, color: color),
        tooltip: tooltip,
        onPressed: enabled ? onPressed : null,
        padding: EdgeInsets.zero,
        splashRadius: size / 2,
        constraints: BoxConstraints(minWidth: size, minHeight: size),
      ),
    );
  }
}

/// 垂直分隔线（用于工具栏内分组）
class ToolbarDivider extends StatelessWidget {
  const ToolbarDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: S.sm),
      color: AppPalette.divider(Theme.of(context).brightness),
    );
  }
}

/// 圆形图标徽章 (数字徽章) — 用于显示数量
class IconBadge extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color? color;
  final double size;

  const IconBadge({
    super.key,
    required this.icon,
    required this.count,
    this.color,
    this.size = 14,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    if (count <= 0) {
      return Icon(icon, size: size, color: AppPalette.textTertiary(Theme.of(context).brightness));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: size - 2, color: c),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(
              fontSize: size - 4,
              color: c,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
