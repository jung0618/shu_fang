// =============================================================================
// ShuFang Design System — Motion Tokens
// =============================================================================
// 动效曲线 + 时长。所有动画必须使用这些常量以保持节奏一致。
// 设计原则：
//   - 80~120ms 用于即时反馈（hover/press）
//   - 180~240ms 用于状态过渡（面板展开/收起）
//   - 320~420ms 用于内容切换（页面转场）
//   - 缓动以 cubic-bezier 为主，避免弹簧式弹跳干扰写作心流
// -----------------------------------------------------------------------------

import 'package:flutter/animation.dart';

class Motion {
  Motion._();

  // -------------------- 时长 --------------------

  /// 即时反馈 - hover/press
  static const Duration micro = Duration(milliseconds: 80);

  /// 短过渡 - 颜色、边框
  static const Duration fast = Duration(milliseconds: 160);

  /// 中等过渡 - 面板、卡片
  static const Duration medium = Duration(milliseconds: 240);

  /// 长过渡 - 页面、抽屉
  static const Duration slow = Duration(milliseconds: 360);

  /// 进入动画总时长 - 长内容
  static const Duration entrance = Duration(milliseconds: 480);

  // -------------------- 曲线 --------------------

  /// 标准进入：开始快、结束慢（适合出场、淡入）
  static const Curve standard = Curves.easeOutCubic;

  /// 强调进入：开始慢、中间快、结束减速（适合入场、推出）
  static const Curve emphasized = Curves.easeOutQuart;

  /// 退出：开始慢、结束快
  static const Curve exit = Curves.easeInCubic;

  /// 线性：用于流式进度
  static const Curve linear = Curves.linear;

  // -------------------- 预置 Tween --------------------

  /// 透明度淡入
  static const double fadeBegin = 0.0;
  static const double fadeEnd = 1.0;

  /// 浮层进入位移
  static const Offset slideFromTop = Offset(0, -8);
  static const Offset slideFromBottom = Offset(0, 8);
  static const Offset slideFromLeft = Offset(-8, 0);
  static const Offset slideFromRight = Offset(8, 0);
}
