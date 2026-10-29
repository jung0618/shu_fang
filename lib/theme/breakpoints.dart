// =============================================================================
// ShuFang Design System — Responsive Breakpoints
// =============================================================================
// 桌面写作 IDE 三档断点:
//   narrow  <  900  —— 单栏紧凑 (小窗口/分屏侧贴)
//   medium  900-1280 —— 双栏标准 (常见笔记本)
//   wide    >= 1280 —— 多栏舒展 (外接显示器)
// 阈值选取依据: NavRail 56 + SidebarTree ~240 + Editor 最小 ~600 ≈ 900
// -----------------------------------------------------------------------------
import 'package:flutter/widgets.dart';

/// 三档断点
enum Breakpoint {
  /// 窄屏 (< 900): 单栏紧凑布局
  narrow,

  /// 中屏 (900-1280): 双栏标准布局
  medium,

  /// 宽屏 (>= 1280): 多栏舒展布局
  wide,
}

/// 断点阈值与查询助手
class AppBreakpoints {
  AppBreakpoints._();

  /// narrow 上限 (不含),低于此值进入窄屏
  static const double narrowMax = 900;

  /// medium 上限 (不含),低于此值进入中屏
  static const double mediumMax = 1280;

  /// 根据当前 [BuildContext] 的窗口宽度判定断点档位
  static Breakpoint of(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < narrowMax) return Breakpoint.narrow;
    if (w < mediumMax) return Breakpoint.medium;
    return Breakpoint.wide;
  }

  /// 根据给定宽度判定断点档位 (供 LayoutBuilder / 测试使用)
  static Breakpoint fromWidth(double width) {
    if (width < narrowMax) return Breakpoint.narrow;
    if (width < mediumMax) return Breakpoint.medium;
    return Breakpoint.wide;
  }

  /// 当前窗口宽度
  static double widthOf(BuildContext context) =>
      MediaQuery.of(context).size.width;
}

/// [BuildContext] 上的断点便捷访问器
extension BreakpointContext on BuildContext {
  /// 当前断点档位
  Breakpoint get breakpoint => AppBreakpoints.of(this);
}
