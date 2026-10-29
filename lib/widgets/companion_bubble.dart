// =============================================================================
// CompanionBubble — 像素助手主动聊天气泡 (D34)
// =============================================================================
// 与写作伙伴共用显示偏好；陪伴提示默认关闭，由用户在设置中开启
// 三种场景: 写作陪伴提示 / 状态提醒 / 上下文感知
// 位置: 左上角, 半透明, 自动消失
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../store/companion_store.dart';
import '../theme/colors.dart';
import '../theme/motion.dart';
import '../theme/radius.dart';
import '../theme/spacing.dart';

/// 气泡情绪类型 (驱动图标 + 配色)
enum BubbleMood {
  greeting, // 问候 (写作陪伴)
  encourage, // 鼓励
  remind, // 提醒 (保存/字数)
  info, // 信息 (章节切换/上下文)
  warning, // 警告 (未保存/错误)
}

/// 单条气泡消息
class CompanionBubbleMessage {
  final String text;
  final BubbleMood mood;
  final Duration duration;

  const CompanionBubbleMessage({
    required this.text,
    this.mood = BubbleMood.info,
    this.duration = const Duration(seconds: 4),
  });
}

/// 全局气泡状态
class CompanionBubbleState {
  final CompanionBubbleMessage? message;
  final bool visible;

  const CompanionBubbleState({this.message, this.visible = false});

  CompanionBubbleState copyWith({
    CompanionBubbleMessage? message,
    bool? visible,
  }) {
    return CompanionBubbleState(
      message: message ?? this.message,
      visible: visible ?? this.visible,
    );
  }

  static const empty = CompanionBubbleState();
}

/// 全局气泡 Controller (Riverpod StateNotifier)
class CompanionBubbleController extends StateNotifier<CompanionBubbleState> {
  Timer? _hideTimer;
  Timer? _clearTimer;

  CompanionBubbleController() : super(CompanionBubbleState.empty);

  /// 显示一条气泡消息
  void show(CompanionBubbleMessage msg) {
    _hideTimer?.cancel();
    _clearTimer?.cancel();
    state = CompanionBubbleState(message: msg, visible: true);
    _hideTimer = Timer(msg.duration, () {
      // 先隐藏 (触发淡出动画), 延迟清除消息
      state = state.copyWith(visible: false);
      _clearTimer = Timer(const Duration(milliseconds: 400), () {
        if (state.visible == false) {
          state = CompanionBubbleState.empty;
        }
      });
    });
  }

  /// 快捷方法: 问候
  void greet(String text) => show(
    CompanionBubbleMessage(
      text: text,
      mood: BubbleMood.greeting,
      duration: const Duration(seconds: 5),
    ),
  );

  /// 快捷方法: 鼓励
  void encourage(String text) => show(
    CompanionBubbleMessage(
      text: text,
      mood: BubbleMood.encourage,
      duration: const Duration(seconds: 4),
    ),
  );

  /// 快捷方法: 提醒
  void remind(String text) => show(
    CompanionBubbleMessage(
      text: text,
      mood: BubbleMood.remind,
      duration: const Duration(seconds: 3),
    ),
  );

  /// 快捷方法: 信息
  void info(String text) => show(
    CompanionBubbleMessage(
      text: text,
      mood: BubbleMood.info,
      duration: const Duration(seconds: 3),
    ),
  );

  /// 快捷方法: 警告
  void warn(String text) => show(
    CompanionBubbleMessage(
      text: text,
      mood: BubbleMood.warning,
      duration: const Duration(seconds: 4),
    ),
  );

  /// 手动隐藏
  void hide() {
    _hideTimer?.cancel();
    _clearTimer?.cancel();
    state = state.copyWith(visible: false);
    _clearTimer = Timer(const Duration(milliseconds: 400), () {
      state = CompanionBubbleState.empty;
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _clearTimer?.cancel();
    super.dispose();
  }
}

/// 全局 Provider
final companionBubbleProvider =
    StateNotifierProvider<CompanionBubbleController, CompanionBubbleState>(
      (ref) => CompanionBubbleController(),
    );

/// 气泡 UI Widget — 挂在 app.dart Stack 顶层, 左上角
class CompanionBubble extends ConsumerWidget {
  const CompanionBubble({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(companionControllerProvider);
    if (!preferences.visible || !preferences.hintsEnabled) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(companionBubbleProvider);
    if (state.message == null) return const SizedBox.shrink();

    final b = Theme.of(context).brightness;
    final msg = state.message!;

    return Positioned(
      top: 48,
      left: S.lg,
      child: AnimatedOpacity(
        opacity: state.visible ? 1.0 : 0.0,
        duration: Motion.medium,
        curve: Curves.easeInOut,
        child: IgnorePointer(
          ignoring: !state.visible,
          child: _BubbleCard(
            message: msg,
            brightness: b,
            onDismiss: () => ref.read(companionBubbleProvider.notifier).hide(),
          ),
        ),
      ),
    );
  }
}

/// 气泡卡片
class _BubbleCard extends StatelessWidget {
  final CompanionBubbleMessage message;
  final Brightness brightness;
  final VoidCallback onDismiss;

  const _BubbleCard({
    required this.message,
    required this.brightness,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    final (icon, accentColor) = _moodStyle(message.mood, isDark);

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
        decoration: BoxDecoration(
          // 半透明背景 (用户要求调透明度)
          color: (isDark ? const Color(0xFF2A2C33) : Colors.white).withValues(
            alpha: 0.92,
          ),
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 情绪图标
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Icon(icon, size: 16, color: accentColor),
            ),
            const SizedBox(width: S.sm),
            // 消息文本
            Flexible(
              child: Text(
                message.text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppPalette.textPrimary(brightness),
                  height: 1.5,
                ),
              ),
            ),
            IconButton(
              tooltip: '关闭提示',
              onPressed: onDismiss,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, size: 14),
            ),
          ],
        ),
      ),
    );
  }

  /// 情绪 → (图标, 强调色)
  (IconData, Color) _moodStyle(BubbleMood mood, bool isDark) {
    switch (mood) {
      case BubbleMood.greeting:
        return (Icons.waving_hand_rounded, AppColors.ai);
      case BubbleMood.encourage:
        return (Icons.favorite_rounded, AppColors.success);
      case BubbleMood.remind:
        return (Icons.notifications_active_rounded, AppColors.warning);
      case BubbleMood.info:
        return (Icons.info_outline_rounded, AppColors.info);
      case BubbleMood.warning:
        return (Icons.warning_amber_rounded, AppColors.error);
    }
  }
}
