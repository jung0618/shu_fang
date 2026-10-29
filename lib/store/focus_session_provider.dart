// 专注模式会话管理 (番茄钟 + 休息)
//
// 设计:
// - focusModeProvider: 总开关 (true=进入专注模式)
// - focusSessionProvider: 会话状态 (phase/remaining/total/dimmed)
// - phase: idle / focusing / resting
// - 默认 25min 专注 + 5min 休息 (可配置)
// - 专注结束 → 自动调高编辑区透明度 (dimmed=true) → 提示休息
// - 休息结束 → 可立即开始下一次专注
// - 可随时叉掉定时器 (回到 idle, 不退出专注模式本身)

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 专注会话阶段
enum FocusPhase {
  /// 空闲 (未开始定时)
  idle,
  /// 专注中 (倒计时)
  focusing,
  /// 休息中 (倒计时)
  resting,
}

/// 专注会话状态
class FocusSessionState {
  final FocusPhase phase;
  final int remainingSeconds; // 当前阶段剩余秒数
  final int focusTotalSeconds; // 专注阶段总时长
  final int restTotalSeconds; // 休息阶段总时长
  final bool dimmed; // 编辑区是否调高透明度 (专注结束提示)

  const FocusSessionState({
    this.phase = FocusPhase.idle,
    this.remainingSeconds = 0,
    this.focusTotalSeconds = 25 * 60,
    this.restTotalSeconds = 5 * 60,
    this.dimmed = false,
  });

  FocusSessionState copyWith({
    FocusPhase? phase,
    int? remainingSeconds,
    int? focusTotalSeconds,
    int? restTotalSeconds,
    bool? dimmed,
  }) {
    return FocusSessionState(
      phase: phase ?? this.phase,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      focusTotalSeconds: focusTotalSeconds ?? this.focusTotalSeconds,
      restTotalSeconds: restTotalSeconds ?? this.restTotalSeconds,
      dimmed: dimmed ?? this.dimmed,
    );
  }

  /// 格式化剩余时间 mm:ss
  String get remainingText {
    final m = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// 进度 0.0-1.0
  double get progress {
    final total = phase == FocusPhase.focusing
        ? focusTotalSeconds
        : phase == FocusPhase.resting
            ? restTotalSeconds
            : 1;
    if (total == 0) return 0;
    return 1.0 - (remainingSeconds / total);
  }
}

/// 专注会话控制器 (Notifier + Timer)
class FocusSessionNotifier extends StateNotifier<FocusSessionState> {
  Timer? _timer;

  FocusSessionNotifier() : super(const FocusSessionState());

  /// 开始专注 (或立即开始下一次, 如果当前是 idle/resting)
  void startFocus() {
    _timer?.cancel();
    state = state.copyWith(
      phase: FocusPhase.focusing,
      remainingSeconds: state.focusTotalSeconds,
      dimmed: false,
    );
    _startTick();
  }

  /// 开始休息
  void startRest() {
    _timer?.cancel();
    state = state.copyWith(
      phase: FocusPhase.resting,
      remainingSeconds: state.restTotalSeconds,
      dimmed: false,
    );
    _startTick();
  }

  /// 叉掉定时器 (回到 idle, 不退出专注模式本身)
  void cancel() {
    _timer?.cancel();
    state = state.copyWith(
      phase: FocusPhase.idle,
      remainingSeconds: 0,
      dimmed: false,
    );
  }

  /// 跳过当前阶段 (专注→休息, 休息→idle 可立即开始下一次)
  void skip() {
    if (state.phase == FocusPhase.focusing) {
      startRest();
    } else {
      cancel();
    }
  }

  /// 设置专注时长 (分钟)
  void setFocusMinutes(int minutes) {
    if (minutes < 1 || minutes > 120) return;
    state = state.copyWith(
      focusTotalSeconds: minutes * 60,
      remainingSeconds: state.phase == FocusPhase.focusing ? minutes * 60 : state.remainingSeconds,
    );
  }

  /// 设置休息时长 (分钟)
  void setRestMinutes(int minutes) {
    if (minutes < 1 || minutes > 60) return;
    state = state.copyWith(
      restTotalSeconds: minutes * 60,
      remainingSeconds: state.phase == FocusPhase.resting ? minutes * 60 : state.remainingSeconds,
    );
  }

  void _startTick() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.remainingSeconds <= 1) {
        _onPhaseComplete();
      } else {
        state = state.copyWith(
          remainingSeconds: state.remainingSeconds - 1,
        );
      }
    });
  }

  void _onPhaseComplete() {
    _timer?.cancel();
    if (state.phase == FocusPhase.focusing) {
      // 专注结束 → 调高透明度提示休息 (不自动开始休息, 等用户确认)
      state = state.copyWith(
        phase: FocusPhase.idle,
        remainingSeconds: 0,
        dimmed: true, // 关键: 调高透明度
      );
    } else if (state.phase == FocusPhase.resting) {
      // 休息结束 → 可立即开始下一次专注
      state = state.copyWith(
        phase: FocusPhase.idle,
        remainingSeconds: 0,
        dimmed: false,
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// 专注会话 Provider
final focusSessionProvider =
    StateNotifierProvider<FocusSessionNotifier, FocusSessionState>((ref) {
  return FocusSessionNotifier();
});
