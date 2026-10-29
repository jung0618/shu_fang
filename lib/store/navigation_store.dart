import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'editor_store.dart';

// ============================================================
// 导航历史栈 (子项目 A)
// ============================================================
// 浏览器式 back/forward 历史, 解决"窗口无法返回"问题.
// appRouteProvider 仍是"当前路由"单一真相源, NavigationController
// 在 push/back/forward 时同步更新 appRouteProvider.
// ============================================================

/// 导航状态
class NavigationState {
  final List<AppRoute> history;
  final int cursor; // 指向当前路由在 history 中的下标

  const NavigationState({
    required this.history,
    required this.cursor,
  });

  /// 当前路由
  AppRoute get current =>
      history.isEmpty ? AppRoute.home : history[cursor.clamp(0, history.length - 1)];

  /// 能否后退
  bool get canBack => cursor > 0;

  /// 能否前进
  bool get canForward => cursor < history.length - 1;

  static const initial = NavigationState(history: [AppRoute.home], cursor: 0);
}

/// 导航控制器 — 管理 back/forward 历史
class NavigationController extends StateNotifier<NavigationState> {
  final Ref _ref;

  NavigationController(this._ref) : super(NavigationState.initial) {
    // 初始化时同步当前路由
    _syncCurrentRoute();
  }

  /// 跳转到新路由 (截断 forward 历史, 符合浏览器语义)
  void push(AppRoute route) {
    final history = [...state.history];
    // 去重: 连续相同路由不入栈
    if (history.isNotEmpty && history[state.cursor] == route) return;
    // 截断 cursor 之后的历史
    final truncated = history.sublist(0, state.cursor + 1);
    truncated.add(route);
    // 上限 50, 丢弃最早
    List<AppRoute> finalHistory = truncated;
    int finalCursor = truncated.length - 1;
    if (truncated.length > 50) {
      finalHistory = truncated.sublist(truncated.length - 50);
      finalCursor = finalHistory.length - 1;
    }
    state = NavigationState(history: finalHistory, cursor: finalCursor);
    _syncCurrentRoute();
  }

  /// 后退
  void back() {
    if (!state.canBack) return;
    state = NavigationState(history: state.history, cursor: state.cursor - 1);
    _syncCurrentRoute();
  }

  /// 前进
  void forward() {
    if (!state.canForward) return;
    state = NavigationState(history: state.history, cursor: state.cursor + 1);
    _syncCurrentRoute();
  }

  /// 回到主页 (快捷入口, 等价 push(home))
  void goHome() => push(AppRoute.home);

  /// 同步当前路由到 appRouteProvider (单一真相源)
  void _syncCurrentRoute() {
    _ref.read(appRouteProvider.notifier).state = state.current;
  }
}

/// 导航控制器 Provider
final navigationControllerProvider =
    StateNotifierProvider<NavigationController, NavigationState>(
  (ref) => NavigationController(ref),
);

/// 派生: 能否后退
final canBackProvider = Provider<bool>((ref) {
  return ref.watch(navigationControllerProvider).canBack;
});

/// 派生: 能否前进
final canForwardProvider = Provider<bool>((ref) {
  return ref.watch(navigationControllerProvider).canForward;
});

/// 派生: 当前路由
final currentRouteProvider = Provider<AppRoute>((ref) {
  return ref.watch(navigationControllerProvider).current;
});
