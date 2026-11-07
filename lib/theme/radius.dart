// =============================================================================
// ShuFang Design System — Radius Tokens
// =============================================================================
// 圆角阶梯。设计意图：圆角越大越"友好/弹出"，越小越"工具/严肃"。
// -----------------------------------------------------------------------------

class R {
  R._();

  /// 1px - 极小（细标签）
  static const double xxs = 1;

  /// 2px - 小标签
  static const double xs = 2;

  /// 4px - 按钮、输入框
  static const double sm = 4;

  /// 6px - 卡片、面板
  static const double md = 6;

  /// 8px - 弹层、对话框
  static const double lg = 8;

  /// 12px - 大卡片、聊天气泡
  static const double xl = 12;

  /// 16px - 浮层面板
  static const double xxl = 16;

  /// 999px - 胶囊 (Chip)
  static const double pill = 999;
}
