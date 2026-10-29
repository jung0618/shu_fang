// =============================================================================
// ShuFang Design System — Elevation & Shadows
// =============================================================================
// 三层投影梯度。设计意图：层次分明但不喧宾夺主。
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';

class Elevation {
  Elevation._();

  /// 0 - 平贴（容器/分组）
  static const double none = 0;

  /// 1 - 悬浮感（卡片、列表项按下）
  static const double low = 1;

  /// 2 - 弹起（工具栏、输入框聚焦）
  static const double medium = 2;

  /// 4 - 浮层（AI 面板、对话框）
  static const double high = 4;

  /// 8 - 顶层（模态、toast）
  static const double top = 8;

  // -------------------- 阴影 --------------------

  /// 浅色模式阴影 - 偏暖
  static List<BoxShadow> shadowLow(Brightness b) {
    final isDark = b == Brightness.dark;
    return [
      BoxShadow(
        color: (isDark ? Colors.black : const Color(0xFF1F1A14))
            .withValues(alpha: isDark ? 0.20 : 0.04),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
  }

  static List<BoxShadow> shadowMedium(Brightness b) {
    final isDark = b == Brightness.dark;
    return [
      BoxShadow(
        color: (isDark ? Colors.black : const Color(0xFF1F1A14))
            .withValues(alpha: isDark ? 0.30 : 0.06),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: (isDark ? Colors.black : const Color(0xFF1F1A14))
            .withValues(alpha: isDark ? 0.18 : 0.03),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
  }

  static List<BoxShadow> shadowHigh(Brightness b) {
    final isDark = b == Brightness.dark;
    return [
      BoxShadow(
        color: (isDark ? Colors.black : const Color(0xFF1F1A14))
            .withValues(alpha: isDark ? 0.40 : 0.08),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: (isDark ? Colors.black : const Color(0xFF1F1A14))
            .withValues(alpha: isDark ? 0.20 : 0.04),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ];
  }
}
