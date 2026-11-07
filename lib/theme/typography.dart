// =============================================================================
// ShuFang Design System — Typography
// =============================================================================
// 设计意图：
//   - UI 走现代几何无衬线（系统字体栈，跨平台一致）
//   - 正文走衬线（中文宋体优先）— 提升长篇阅读舒适度
//   - 类型阶梯对齐 Material 3 named styles，但微调字重与字高
//   - 字符密度合理：UI 紧凑、正文舒展
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';

import 'colors.dart';

class AppTypography {
  AppTypography._();

  // -------------------- 字体族 --------------------

  /// UI 字体（西文 + 中文回退到 PingFang/思源）
  static const String _uiFamily = 'system-ui';

  /// 正文/编辑器字体（中文优先宋体，西文衬线回退）
  static const String _serifFamily = 'serif';

  // -------------------- 阶梯定义 --------------------

  /// 大标题 - 32sp，900 字重
  static const TextStyle displayLarge = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 32,
    height: 1.20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
  );

  /// 标题 1 - 24sp
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 24,
    height: 1.30,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  /// 标题 2 - 20sp
  static const TextStyle headlineMedium = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 20,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );

  /// 标题 3 - 17sp
  static const TextStyle titleLarge = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 17,
    height: 1.40,
    fontWeight: FontWeight.w600,
  );

  /// 副标题 - 14sp 中等
  static const TextStyle titleMedium = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w500,
  );

  /// 小标题 - 13sp 中等
  static const TextStyle titleSmall = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w500,
  );

  /// 正文大 - 16sp (编辑器正文)
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: _serifFamily,
    fontSize: 16,
    height: 1.80,
    fontWeight: FontWeight.w400,
  );

  /// 正文中 - 14sp
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 14,
    height: 1.55,
    fontWeight: FontWeight.w400,
  );

  /// 正文小 - 13sp
  static const TextStyle bodySmall = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 13,
    height: 1.50,
    fontWeight: FontWeight.w400,
  );

  /// 标签大 - 13sp
  static const TextStyle labelLarge = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 13,
    height: 1.40,
    fontWeight: FontWeight.w500,
  );

  /// 标签中 - 12sp
  static const TextStyle labelMedium = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 12,
    height: 1.40,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  /// 标签小 - 11sp
  static const TextStyle labelSmall = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 11,
    height: 1.40,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
  );

  /// 代码 - 13sp 等宽
  static const TextStyle code = TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    height: 1.55,
    fontWeight: FontWeight.w400,
  );

  // -------------------- Material 3 ThemeData 桥接 --------------------

  /// 将上述 token 装入 Material 3 命名样式。
  /// 组件应该用 context.textTheme.titleLarge 而不是直接 TextStyle。
  static TextTheme toTextTheme(ColorScheme scheme) {
    return TextTheme(
      displayLarge: displayLarge.copyWith(color: scheme.onSurface),
      displayMedium: displayLarge.copyWith(
        fontSize: 28,
        color: scheme.onSurface,
      ),
      displaySmall: displayLarge.copyWith(
        fontSize: 24,
        color: scheme.onSurface,
      ),
      headlineLarge: headlineLarge.copyWith(color: scheme.onSurface),
      headlineMedium: headlineMedium.copyWith(color: scheme.onSurface),
      headlineSmall: headlineMedium.copyWith(
        fontSize: 18,
        color: scheme.onSurface,
      ),
      titleLarge: titleLarge.copyWith(color: scheme.onSurface),
      titleMedium: titleMedium.copyWith(color: scheme.onSurface),
      titleSmall: titleSmall.copyWith(color: scheme.onSurface),
      bodyLarge: bodyLarge.copyWith(color: scheme.onSurface),
      bodyMedium: bodyMedium.copyWith(color: scheme.onSurface),
      bodySmall: bodySmall.copyWith(color: scheme.onSurfaceVariant),
      labelLarge: labelLarge.copyWith(color: scheme.onSurface),
      labelMedium: labelMedium.copyWith(color: scheme.onSurfaceVariant),
      labelSmall: labelSmall.copyWith(color: scheme.onSurfaceVariant),
    );
  }
}

/// TextTheme 扩展方法，便于组件使用语义化命名。
extension AppTextThemeX on TextTheme {
  /// 编辑器正文（衬线，宽松行距）
  TextStyle get editorBody => AppTypography.bodyLarge;

  /// 章节标题（编辑器顶部）
  TextStyle get chapterTitle => AppTypography.headlineLarge;
}

/// 文本上下文扩展。
extension AppTextContextX on BuildContext {
  /// AppPalette 文本色助手
  Color get textPrimary => AppPalette.textPrimary(Theme.of(this).brightness);

  Color get textSecondary => AppPalette.textSecondary(Theme.of(this).brightness);

  Color get textTertiary => AppPalette.textTertiary(Theme.of(this).brightness);
}
