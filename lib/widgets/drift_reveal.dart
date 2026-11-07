// 漂移避让式交互揭示模式 — 通用组件
//
// Phase 3.1 限定用法: 仅主页快速入口条的 emoji 按钮
// - 默认态: 仅 emoji (无文字)
// - hover: emoji 淡出, 文字展开 (单次切换, 不共存)
// - externalHint: emoji 外圈视觉引导 (chevron/边框呼吸), 暗示"hover 有更多"
// - 绝不用于: 书卡、设定文件卡、导航容器
//
// 设计模式: 双层堆叠 (占位层 + 功能层) + 临近感知触发 + 定向避让位移 + 可逆闭环

import 'package:flutter/material.dart';

/// 漂移避让方向枚举
enum DriftDirection {
  left,
  right,
  up,
  down,
}

/// 漂移避让式交互揭示组件
///
/// Phase 3.1 限定用法: 主页快速入口条 emoji 按钮
/// ```dart
/// DriftReveal(
///   driftDirection: DriftDirection.up,
///   placeholder: Text('💡', style: TextStyle(fontSize: 32)),
///   reveal: Text('灵感', style: TextStyle(fontSize: 14)),
///   externalHint: DriftHint.chevronRight,
/// )
/// ```
class DriftReveal extends StatefulWidget {
  /// 占位层 — 默认态显示 (Phase 3.1: 仅 emoji, 无文字)
  final Widget placeholder;

  /// 功能层 — 悬停后揭示 (Phase 3.1: 文字描述, emoji → text 单次切换)
  final Widget reveal;

  /// 漂移方向 (占位层移动方向) — Phase 3.5b: 默认改为 up 但 driftDistance=0 (纯淡出)
  final DriftDirection driftDirection;

  /// 漂移距离 (像素) — Phase 3.5b: 默认 0 (纯淡出, 不做位移, 更丝滑)
  final double driftDistance;

  /// 感应热区扩展 (相对占位层视觉范围的外扩, 默认 4px)
  final double hoverPadding;

  /// 动画时长 — Phase 3.5b: 800ms (慢得多, 丝滑淡出)
  final Duration duration;

  /// 缓动曲线 — Phase 3.5b: easeInOut (淡出淡入更自然)
  final Curve curve;

  /// 离开延迟 (避免鼠标短暂划过频繁触发, 默认 200ms)
  final Duration leaveDelay;

  /// 占位层是否在漂移时淡出到透明 (默认 true)
  final bool fadePlaceholder;

  /// 功能层是否淡入 (默认 true)
  final bool fadeReveal;

  /// 外部视觉引导 (Phase 3.1 新增)
  /// Phase 3.5b: hint 内嵌在 placeholder 内部右下角, 不超出按钮边界
  final DriftHint? externalHint;

  const DriftReveal({
    super.key,
    required this.placeholder,
    required this.reveal,
    this.driftDirection = DriftDirection.up,
    this.driftDistance = 0,
    this.hoverPadding = 4,
    this.duration = const Duration(milliseconds: 800),
    this.curve = Curves.easeInOut,
    this.leaveDelay = const Duration(milliseconds: 200),
    this.fadePlaceholder = true,
    this.fadeReveal = true,
    this.externalHint,
  });

  @override
  State<DriftReveal> createState() => _DriftRevealState();
}

/// 外部视觉引导样式 (Phase 3.1)
enum DriftHint {
  /// 右下角小 chevron, 暗示"hover 展开"
  chevronRight,
  /// 边框呼吸 (透明度循环), 暗示"可交互"
  borderBreath,
  /// 小箭头向上, 暗示"向上展开"
  arrowUp,
}

class _DriftRevealState extends State<DriftReveal> {
  bool _hovering = false;

  Offset get _driftOffset {
    final d = widget.driftDistance;
    switch (widget.driftDirection) {
      case DriftDirection.left:
        return Offset(-d, 0);
      case DriftDirection.right:
        return Offset(d, 0);
      case DriftDirection.up:
        return Offset(0, -d);
      case DriftDirection.down:
        return Offset(0, d);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.hoverPadding;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) {
        Future.delayed(widget.leaveDelay, () {
          if (mounted) setState(() => _hovering = false);
        });
      },
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            // 功能层 (底层) — 默认隐藏, 悬停时淡入
            AnimatedOpacity(
              opacity: _hovering ? 1.0 : 0.0,
              duration: widget.duration,
              curve: widget.curve,
              child: IgnorePointer(
                ignoring: !_hovering,
                child: widget.reveal,
              ),
            ),
            // 占位层 (顶层) — 默认覆盖, 悬停时淡出 (Phase 3.5b: driftDistance=0 不位移)
            Positioned.fill(
              child: AnimatedSlide(
                offset: _hovering ? _driftOffset : Offset.zero,
                duration: widget.duration,
                curve: widget.curve,
                child: AnimatedOpacity(
                  opacity: _hovering && widget.fadePlaceholder ? 0.0 : 1.0,
                  duration: widget.duration,
                  curve: widget.curve,
                  child: widget.placeholder,
                ),
              ),
            ),
            // 外部视觉引导 (Phase 3.5b) — 内嵌在按钮内部右下角, 不超出边界
            // 用 Positioned + 负值会超出, 这里用 4px 内边距确保 hint 在按钮内
            if (widget.externalHint != null)
              Positioned(
                right: 4,
                bottom: 4,
                child: AnimatedOpacity(
                  opacity: _hovering ? 0.0 : 0.45,
                  duration: widget.duration,
                  curve: widget.curve,
                  child: _buildHint(widget.externalHint!),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHint(DriftHint hint) {
    switch (hint) {
      case DriftHint.chevronRight:
        return const Icon(
          Icons.chevron_right_rounded,
          size: 12,
          color: Color(0xFF888888),
        );
      case DriftHint.arrowUp:
        return const Icon(
          Icons.keyboard_arrow_up_rounded,
          size: 12,
          color: Color(0xFF888888),
        );
      case DriftHint.borderBreath:
        // 边框呼吸由容器实现, 这里返回空 (容器层处理)
        return const SizedBox.shrink();
    }
  }
}
