// 专注模式浮动面板
//
// 位置: 屏幕右上角 (默认), 可拖拽移动
// 功能:
// - 显示当前阶段 (专注中 / 休息中 / 专注结束)
// - 倒计时 mm:ss + 进度环
// - 开始专注 / 开始休息 / 跳过 / 叉掉定时器
// - 退出专注模式按钮 (独立, 总可见)
// - 顶部标题栏可拖拽移动面板位置
// - 编辑区透明度遮罩 (专注结束时 dimmed=true)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../store/editor_store.dart';
import '../store/focus_session_provider.dart';
import '../theme/colors.dart';
import '../theme/motion.dart';
import '../theme/spacing.dart';

/// 专注模式浮动面板 (默认右上角, 可拖拽)
class FocusPanel extends ConsumerStatefulWidget {
  const FocusPanel({super.key});

  @override
  ConsumerState<FocusPanel> createState() => _FocusPanelState();
}

class _FocusPanelState extends ConsumerState<FocusPanel> {
  // 面板位置 (相对 Stack 右上角偏移, 默认 top:12, right:12)
  Offset _position = const Offset(0, 0);
  // 拖拽起点记录 (用于计算 delta)
  Offset? _dragStart;

  void _onPanStart(DragStartDetails d) {
    _dragStart = d.globalPosition;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_dragStart == null) return;
    setState(() {
      _position = _position + d.delta;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(focusSessionProvider);
    final b = Theme.of(context).brightness;

    // 默认右上角 (right:12, top:12), 再叠加拖拽偏移
    // _position.dx 正 = 向右, 负 = 向左; 这里用 right - dx 实现左拖
    final right = 12 - _position.dx;
    final top = 12 + _position.dy;

    return Positioned(
      top: top < 0 ? 0 : top,
      right: right < 0 ? 0 : right,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: AppPalette.surface(b),
        child: Container(
          width: 240,
          padding: const EdgeInsets.all(S.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: session.phase == FocusPhase.focusing
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : session.phase == FocusPhase.resting
                      ? AppColors.success.withValues(alpha: 0.4)
                      : AppPalette.divider(b),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部标题栏: 可拖拽手柄 + 阶段标签 + 叉掉按钮
              MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  child: Row(
                  children: [
                    Icon(
                      session.phase == FocusPhase.focusing
                          ? Icons.center_focus_strong_rounded
                          : session.phase == FocusPhase.resting
                              ? Icons.coffee_rounded
                              : session.dimmed
                                  ? Icons.bedtime_rounded
                                  : Icons.timer_outlined,
                      size: 16,
                      color: session.phase == FocusPhase.focusing
                          ? AppColors.primary
                          : session.phase == FocusPhase.resting
                              ? AppColors.success
                              : AppPalette.textSecondary(b),
                    ),
                    const SizedBox(width: S.xs),
                    Text(
                      session.phase == FocusPhase.focusing
                          ? '专注中'
                          : session.phase == FocusPhase.resting
                              ? '休息中'
                              : session.dimmed
                                  ? '专注完成 · 该休息了'
                                  : '专注定时器',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: session.phase == FocusPhase.focusing
                                ? AppColors.primary
                                : session.phase == FocusPhase.resting
                                    ? AppColors.success
                                    : AppPalette.textSecondary(b),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Spacer(),
                    // 拖拽提示图标 (暗示可移动)
                    Icon(Icons.drag_indicator_rounded,
                        size: 14, color: AppPalette.textTertiary(b)),
                    const SizedBox(width: S.xs),
                    // 叉掉定时器 (不退出专注模式本身)
                    if (session.phase != FocusPhase.idle)
                      InkWell(
                        onTap: () =>
                            ref.read(focusSessionProvider.notifier).cancel(),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(Icons.close,
                              size: 14, color: AppPalette.textTertiary(b)),
                        ),
                      ),
                  ],
                ),
                ),
              ),
              const SizedBox(height: S.sm),
              // 倒计时显示
              if (session.phase != FocusPhase.idle)
                _CountdownDisplay(session: session, brightness: b)
              else
                _IdleControls(session: session, brightness: b, ref: ref),
              const SizedBox(height: S.sm),
              // 控制按钮
              if (session.phase != FocusPhase.idle)
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () =>
                            ref.read(focusSessionProvider.notifier).skip(),
                        icon: const Icon(Icons.skip_next, size: 14),
                        label: const Text('跳过', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          minimumSize: const Size(0, 28),
                        ),
                      ),
                    ),
                  ],
                ),
              // 退出专注模式按钮 (独立, 总可见)
              const Divider(height: 1),
              const SizedBox(height: S.xs),
              SizedBox(
                height: 28,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    ref.read(focusSessionProvider.notifier).cancel();
                    ref.read(focusModeProvider.notifier).state = false;
                  },
                  icon: const Icon(Icons.fullscreen_exit, size: 14),
                  label: const Text('退出专注模式',
                      style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 0),
                    minimumSize: const Size(0, 28),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 倒计时显示 (圆形进度 + 数字)
class _CountdownDisplay extends StatelessWidget {
  final FocusSessionState session;
  final Brightness brightness;
  const _CountdownDisplay({required this.session, required this.brightness});

  @override
  Widget build(BuildContext context) {
    final color = session.phase == FocusPhase.focusing
        ? AppColors.primary
        : AppColors.success;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: session.progress,
                strokeWidth: 3,
                color: color,
                backgroundColor:
                    AppPalette.divider(brightness),
              ),
              Center(
                child: Icon(
                  session.phase == FocusPhase.focusing
                      ? Icons.center_focus_strong_rounded
                      : Icons.coffee_rounded,
                  size: 16,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: S.sm),
        Text(
          session.remainingText,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: AppPalette.textPrimary(brightness),
          ),
        ),
      ],
    );
  }
}

/// idle 状态控件 (开始专注 / 开始休息 / 时长设置)
class _IdleControls extends ConsumerWidget {
  final FocusSessionState session;
  final Brightness brightness;
  final WidgetRef ref;
  const _IdleControls(
      {required this.session, required this.brightness, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // dimmed 提示 (专注刚结束)
        if (session.dimmed)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: S.sm, vertical: S.xs),
            margin: const EdgeInsets.only(bottom: S.sm),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.light_mode_outlined,
                    size: 12, color: AppColors.warning),
                const SizedBox(width: S.xs),
                Expanded(
                  child: Text(
                    '编辑区已调淡, 建议休息',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 时长设置 (折叠态)
        Row(
          children: [
            _MinuteSelector(
              label: '专注',
              minutes: session.focusTotalSeconds ~/ 60,
              color: AppColors.primary,
              onChanged: (m) =>
                  ref.read(focusSessionProvider.notifier).setFocusMinutes(m),
            ),
            const SizedBox(width: S.sm),
            _MinuteSelector(
              label: '休息',
              minutes: session.restTotalSeconds ~/ 60,
              color: AppColors.success,
              onChanged: (m) =>
                  ref.read(focusSessionProvider.notifier).setRestMinutes(m),
            ),
          ],
        ),
        const SizedBox(height: S.sm),
        // 主按钮
        FilledButton.icon(
          onPressed: () =>
              ref.read(focusSessionProvider.notifier).startFocus(),
          icon: const Icon(Icons.play_arrow, size: 16),
          label: Text(session.dimmed ? '开始下一次专注' : '开始专注'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 32),
          ),
        ),
      ],
    );
  }
}

/// 分钟选择器 (下拉)
class _MinuteSelector extends StatelessWidget {
  final String label;
  final int minutes;
  final Color color;
  final ValueChanged<int> onChanged;
  const _MinuteSelector({
    required this.label,
    required this.minutes,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: AppPalette.textSecondary(Theme.of(context).brightness))),
          const SizedBox(width: S.xs),
          Expanded(
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: S.xs),
              decoration: BoxDecoration(
                border: Border.all(
                    color: color.withValues(alpha: 0.3), width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: minutes,
                  isExpanded: true,
                  style: TextStyle(fontSize: 11, color: color),
                  items: [5, 10, 15, 20, 25, 30, 45, 60]
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text('$m 分'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onChanged(v);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 编辑区透明度遮罩 (专注结束时 dimmed=true, 调高透明度)
class FocusDimOverlay extends ConsumerWidget {
  final Widget child;
  const FocusDimOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(focusSessionProvider);
    // dimmed 时给编辑区加半透明白色遮罩 (调高透明度 = 让编辑区变淡)
    return Stack(
      children: [
        child,
        if (session.dimmed)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: Motion.entrance,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ),
      ],
    );
  }
}
