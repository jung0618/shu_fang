// =============================================================================
// ShuFang Design System — Color Tokens
// =============================================================================
// 设计意图（避免任何第三方命名/色值复制，纯原创）：
//   - 暖白纸张感背景（写作场景舒适度）
//   - 暖灰中性阶梯（替代冷灰，更护眼）
//   - 主色：克制蓝青（传达"工具/专业"）
//   - AI 强调：暖紫（区分 AI/普通）
//   - 语义：成功/警告/错误/信息四档
//   - 双主题对称：亮暗都基于 12 阶灰度派生
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';

/// 语义色集。所有 UI 组件只引用 AppColors.* 静态字段，
/// 不直接写 Color(0xFFxxxxxx) — 这样改主题只改一处。
class AppColors {
  AppColors._();

  // ===========================================================================
  // 1. 主色 (Primary) — 克制蓝青
  // ===========================================================================
  // 偏中性蓝，饱和度刻意压低。写作时长时间盯视不易疲劳。

  /// 主色 - 500 (默认)
  static const Color primary = Color(0xFF2F6FEB);

  /// 主色 - 600 (hover)
  static const Color primaryHover = Color(0xFF1F5BD0);

  /// 主色 - 700 (pressed)
  static const Color primaryPressed = Color(0xFF1A4BAB);

  /// 主色 - 100 (容器背景)
  static const Color primaryContainer = Color(0xFFE2ECFF);

  /// 主色 - 800 (主色之上的文字)
  static const Color onPrimaryContainer = Color(0xFF0E2A5C);

  // ===========================================================================
  // 2. 强调色 (Accent / AI) — 暖紫
  // ===========================================================================
  // 用于 AI 功能。视觉上明显区别于"普通"操作。

  /// AI 强调色 - 500
  static const Color ai = Color(0xFF8B5CF6);

  /// AI 强调色 - 600
  static const Color aiHover = Color(0xFF7C4DEF);

  /// AI 渐变起点
  static const Color aiGradientStart = Color(0xFF8B5CF6);

  /// AI 渐变终点
  static const Color aiGradientEnd = Color(0xFFEC4899);

  /// AI 容器
  static const Color aiContainer = Color(0xFFF1E8FE);

  /// AI 容器之上文字
  static const Color onAiContainer = Color(0xFF3B1E70);

  // ===========================================================================
  // 3. 语义色
  // ===========================================================================

  /// 成功 (绿)
  static const Color success = Color(0xFF10A37F);
  static const Color successContainer = Color(0xFFD6F4E8);
  static const Color onSuccessContainer = Color(0xFF08392B);

  /// 警告 (琥珀)
  static const Color warning = Color(0xFFEA8A1A);
  static const Color warningContainer = Color(0xFFFCEFD9);
  static const Color onWarningContainer = Color(0xFF552D00);

  /// 错误 (暖红，非纯红)
  static const Color error = Color(0xFFD64545);
  static const Color errorContainer = Color(0xFFFCDDDB);
  static const Color onErrorContainer = Color(0xFF5C1212);

  /// 信息 (青蓝)
  static const Color info = Color(0xFF0EA5C9);
  static const Color infoContainer = Color(0xFFD3F1F8);
  static const Color onInfoContainer = Color(0xFF063C4A);

  // ===========================================================================
  // 4. 中性 (Neutral) — 暖灰阶梯
  // ===========================================================================
  // 全部基于 0xFF18 的暖灰轴线，而非纯冷灰。

  /// 50 - 最浅 (页面背景)
  static const Color neutral50 = Color(0xFFFAF9F7);

  /// 100 - 卡片/容器
  static const Color neutral100 = Color(0xFFF2F0EC);

  /// 150 - 次级容器 (M3 surfaceContainerLow)
  static const Color neutral150 = Color(0xFFEBE8E2);

  /// 200 - 容器高亮 (M3 surfaceContainerHigh)
  static const Color neutral200 = Color(0xFFE4E0D8);

  /// 300 - 边框浅
  static const Color neutral300 = Color(0xFFD4CFC4);

  /// 400 - 边框
  static const Color neutral400 = Color(0xFFB5AE9F);

  /// 500 - 占位符/次要文字
  static const Color neutral500 = Color(0xFF8A8478);

  /// 600 - 三级文字
  static const Color neutral600 = Color(0xFF5F5A50);

  /// 700 - 二级文字
  static const Color neutral700 = Color(0xFF3F3B33);

  /// 800 - 主要文字
  static const Color neutral800 = Color(0xFF272420);

  /// 900 - 标题/强调
  static const Color neutral900 = Color(0xFF15130F);

  // ===========================================================================
  // 5. 暗色主题覆盖
  // ===========================================================================
  // 暗色也用暖灰基底，避免纯黑刺眼。

  /// 暗色 - 0 (页面背景)
  static const Color darkBg = Color(0xFF161512);

  /// 暗色 - 1 (容器)
  static const Color darkSurface = Color(0xFF1F1D19);

  /// 暗色 - 2 (容器高)
  static const Color darkSurfaceHigh = Color(0xFF272420);

  /// 暗色 - 3 (容器更高)
  static const Color darkSurfaceHighest = Color(0xFF302D27);

  /// 暗色 - 边框
  static const Color darkBorder = Color(0xFF3A3630);

  /// 暗色 - 主文字
  static const Color darkTextPrimary = Color(0xFFEDE7DA);

  /// 暗色 - 次文字
  static const Color darkTextSecondary = Color(0xFFB5AE9F);

  /// 暗色 - 三级文字
  static const Color darkTextTertiary = Color(0xFF7A7468);

  // ===========================================================================
  // 6. 荧光笔（写作专用）— 保持原项目的 5 色
  // ===========================================================================
  // 略作调整：提高不透明度，让 minimap 中更清晰。

  static const Color highlighterYellow = Color(0xFFFFD93D);
  static const Color highlighterRed = Color(0xFFFF6B6B);
  static const Color highlighterBlue = Color(0xFF5B8DEF);
  static const Color highlighterGreen = Color(0xFF51CF66);
  static const Color highlighterPurple = Color(0xFFB197FC);
}

/// 主题感知的颜色助手。
/// 让组件编写时不用关心是 light 还是 dark。
class AppPalette {
  AppPalette._();

  /// 页面背景
  static Color scaffold(Brightness b) =>
      b == Brightness.dark ? AppColors.darkBg : AppColors.neutral50;

  /// 表面 (卡片/容器)
  static Color surface(Brightness b) =>
      b == Brightness.dark ? AppColors.darkSurface : Colors.white;

  /// 容器高亮
  static Color surfaceHigh(Brightness b) => b == Brightness.dark
      ? AppColors.darkSurfaceHigh
      : AppColors.neutral100;

  /// 容器最高
  static Color surfaceHighest(Brightness b) => b == Brightness.dark
      ? AppColors.darkSurfaceHighest
      : AppColors.neutral150;

  /// 边框
  static Color border(Brightness b) =>
      b == Brightness.dark ? AppColors.darkBorder : AppColors.neutral300;

  /// 分割线
  static Color divider(Brightness b) =>
      b == Brightness.dark ? AppColors.darkBorder : AppColors.neutral200;

  /// 主要文字
  static Color textPrimary(Brightness b) =>
      b == Brightness.dark ? AppColors.darkTextPrimary : AppColors.neutral900;

  /// 次要文字
  static Color textSecondary(Brightness b) =>
      b == Brightness.dark ? AppColors.darkTextSecondary : AppColors.neutral600;

  /// 三级文字/占位符
  static Color textTertiary(Brightness b) =>
      b == Brightness.dark ? AppColors.darkTextTertiary : AppColors.neutral500;

  /// 禁用
  static Color disabled(Brightness b) =>
      b == Brightness.dark ? AppColors.darkTextTertiary : AppColors.neutral400;
}

// ===========================================================================
// 7. 热力图色板 (写作活动强度)
// ===========================================================================
// 5 级强度: 0=无活动 ~ 4=高活动
// 深色模式: 深灰→浅绿 (低对比, 不干扰写作)
// 浅色模式: 浅灰→深绿 (高对比, 清晰可见)

class HeatmapPalette {
  HeatmapPalette._();

  /// 深色模式 5 级
  static const List<Color> dark = [
    Color(0xFF2A2C33),
    Color(0xFF3B5B45),
    Color(0xFF4F8F69),
    Color(0xFF65BB89),
    Color(0xFF7FE3A7),
  ];

  /// 浅色模式 5 级
  static const List<Color> light = [
    Color(0xFFEEF0F2),
    Color(0xFFC8E6D2),
    Color(0xFF95D6AE),
    Color(0xFF5FC588),
    Color(0xFF2FA864),
  ];

  /// 按强度级别取色 (0-4, 超出范围 clamp)
  static Color colorForLevel(int level, Brightness b) {
    final palette = b == Brightness.dark ? dark : light;
    return palette[level.clamp(0, palette.length - 1)];
  }
}

// ===========================================================================
// 8. 书籍封面渐变 (预设 3 组 + 默认)
// ===========================================================================

class BookCoverGradients {
  BookCoverGradients._();

  static const List<Color> purple = [Color(0xFF5E35B1), Color(0xFF8E24AA)];
  static const List<Color> blue = [Color(0xFF1976D2), Color(0xFF0288D1)];
  static const List<Color> orange = [Color(0xFFE65100), Color(0xFFFF6F00)];
  static const List<Color> defaultValue = [AppColors.primary, AppColors.info];

  static List<Color> forId(String id) {
    switch (id) {
      case 'book1':
        return purple;
      case 'book2':
        return blue;
      case 'book3':
        return orange;
      default:
        return defaultValue;
    }
  }
}
