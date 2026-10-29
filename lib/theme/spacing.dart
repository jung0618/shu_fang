// =============================================================================
// ShuFang Design System — Spacing Tokens
// =============================================================================
// 4px 基础栅格。所有间距值都从此派生，避免散落的"魔法数字"。
// -----------------------------------------------------------------------------

/// 4px 基础栅格 + 6/8/12/16/20/24/32/40/56 阶梯。
class S {
  S._();

  /// 0px
  static const double zero = 0;

  /// 2px - 细颗粒（图标内 padding）
  static const double xxs = 2;

  /// 4px - 行内紧凑间距
  static const double xs = 4;

  /// 6px - 元素内紧凑
  static const double s = 6;

  /// 8px - 控件内边距
  static const double sm = 8;

  /// 12px - 块内默认
  static const double md = 12;

  /// 16px - 段落、卡片内边距
  static const double lg = 16;

  /// 20px - 区域边距
  static const double xl = 20;

  /// 24px - 大块间隔
  static const double xxl = 24;

  /// 32px - 章节大间隔
  static const double xxxl = 32;

  /// 40px - 容器外边距
  static const double huge = 40;

  /// 56px - 顶部工具区
  static const double giant = 56;
}
