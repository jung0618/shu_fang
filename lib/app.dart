import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'config/flavor.dart';
import 'services/engine_launcher.dart';
import 'services/chapter_save_queue.dart';
import 'services/safe_file_writer.dart';
import 'store/workspace_store.dart';
import 'store/workspace_session_reset.dart';
import 'store/editor_store.dart';
import 'store/navigation_store.dart';
import 'pages/editor_page.dart';
import 'pages/inspire_page.dart';
import 'pages/workspace_page.dart';
import 'pages/project_page.dart';
import 'pages/companion_preview_page.dart';
import 'pages/home_dashboard_page.dart';
import 'pages/app_settings_page.dart';
import 'theme/app_theme.dart';
import 'widgets/companion_bubble.dart';
import 'widgets/focus_panel.dart';
import 'widgets/nav_rail.dart';
import 'widgets/search_dialog.dart';

/// 入口应用
class ShuFangApp extends ConsumerStatefulWidget {
  final bool manageWindow;
  const ShuFangApp({super.key, this.manageWindow = false});

  @override
  ConsumerState<ShuFangApp> createState() => _ShuFangAppState();
}

class _ShuFangAppState extends ConsumerState<ShuFangApp> with WindowListener {
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    if (widget.manageWindow) windowManager.addListener(this);
    // D22 修复: 改为后台异步探测, 不再阻塞主界面
    // 用户面不需要引擎, 引擎状态只供 AI 聊天等高级功能异步使用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) EngineLauncher.probeEngine(ref);
    });
  }

  @override
  void dispose() {
    if (widget.manageWindow) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (_closing || ref.read(workspaceControllerProvider).isLoading) return;
    setState(() {
      _closing = true;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await chapterSaveQueue.flushAll();
    await SafeFileWriter.flushAll();
    if (ok) {
      await windowManager.destroy();
      return;
    }
    if (!mounted) return;
    setState(() {
      _closing = false;
    });
    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext != null && dialogContext.mounted && mounted) {
      await showDialog<void>(
        context: dialogContext,
        builder:
            (context) => AlertDialog(
              title: const Text('正文尚未保存'),
              content: const Text(
                '写入失败，草稿仍保留在窗口中。请检查数据目录权限或磁盘空间，再按 Ctrl+S 重试。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('返回写作'),
                ),
              ],
            ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final route = ref.watch(appRouteProvider);
    final focus = ref.watch(focusModeProvider);
    // Open the local writing shell after a workspace has been selected.
    final workspaceState = ref.watch(workspaceControllerProvider);
    final hasWorkspace = workspaceState.workspace != null;
    ref.listen(workspaceControllerProvider, (previous, next) {
      if (next.isLoading && previous?.isLoading != true) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
      if (previous?.revision != next.revision) {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
        resetWorkspaceSession(ref);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) EngineLauncher.probeEngine(ref);
        });
      }
    });
    // D34: 激活像素助手气泡 watcher (保存/章节/字数)
    if (hasWorkspace) {
      ref.watch(companionSaveWatcher);
      ref.watch(companionChapterWatcher);
      ref.watch(companionWordCountWatcher);
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: kShuFangAppTitle,
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      // T-11: 接入设计系统 AppTheme (替换 ColorScheme.fromSeed 硬编码)
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      builder: (context, child) {
        // 专注模式：隐藏侧栏+AI 面板, 显示 FocusPanel (定时器+退出按钮)
        return Stack(
          children: [
            if (child != null) child,
            if (focus && hasWorkspace) const FocusPanel(),
            if (_closing || workspaceState.isLoading) ...[
              const ModalBarrier(dismissible: false, color: Color(0x33000000)),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        );
      },
      // Workspace selection precedes the writing shell.
      home:
          !hasWorkspace
              ? const WorkspacePage()
              : _EngineGate(
                key: ValueKey(workspaceState.revision),
                child: Row(
                  children: [
                    // 侧边导航栏 (专注模式隐藏)
                    if (!focus) const NavRail(),
                    Expanded(
                      child: switch (route) {
                        AppRoute.home => const HomeDashboardPage(),
                        AppRoute.editor => const EditorPage(),
                        AppRoute.project => const ProjectPage(),
                        // D26 #6/#10: review/preset 从顶级路由移除, 整合到项目 Tab
                        // 内部 route 名保留 engineering 以兼容旧引用, 显示已改为"预设"
                        AppRoute.review => const ProjectPage(initialTab: 4),
                        AppRoute.engineering => const ProjectPage(
                          initialTab: 5,
                        ),
                        AppRoute.companion => const CompanionPreviewPage(),
                        // D37 Phase 2-1 (P0-9): 灵感页接线 — 直接渲染 InspirePage (348 行功能页)
                        // 之前是 HomeDashboardPage(initialInspireFocus: true) 滚回主页自身, 死路
                        AppRoute.inspire => const InspirePage(),
                        AppRoute.settings => const AppSettingsPage(),
                      },
                    ),
                  ],
                ),
              ),
    );
  }
}

/// Writing remains available while the optional engine is disconnected.
class _EngineGate extends StatelessWidget {
  final Widget child;
  const _EngineGate({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Stack(
    children: [_GlobalShortcutHandler(child: child), const CompanionBubble()],
  );
}

class _GlobalShortcutHandler extends ConsumerStatefulWidget {
  final Widget child;
  const _GlobalShortcutHandler({required this.child});

  @override
  ConsumerState<_GlobalShortcutHandler> createState() =>
      _GlobalShortcutHandlerState();
}

class _GlobalShortcutHandlerState
    extends ConsumerState<_GlobalShortcutHandler> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (ref.read(workspaceControllerProvider).isLoading) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyS) {
      _handleSave();
      return KeyEventResult.handled;
    }
    // 撤销 / 重做
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      ref.read(editorUndoControllerProvider)?.undo();
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyY) {
      ref.read(editorUndoControllerProvider)?.redo();
      return KeyEventResult.handled;
    }
    // 切换侧边栏 / AI 面板
    // D50-8 (L7/L8): 写入源 Provider (sidebarCollapsedProvider/aiPanelExpandedProvider),
    // 而非派生 Provider (showSidebarProvider/showAiPanelProvider)
    // (派生 Provider 被直接写入不会反向更新源, 导致 watcher 不触发, 设置重启丢失)
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyB) {
      ref.read(sidebarCollapsedProvider.notifier).state =
          !ref.read(sidebarCollapsedProvider);
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyJ) {
      ref.read(aiPanelExpandedProvider.notifier).state =
          !ref.read(aiPanelExpandedProvider);
      return KeyEventResult.handled;
    }
    if (isCtrl && isShift && event.logicalKey == LogicalKeyboardKey.keyF) {
      _handleSearch();
      return KeyEventResult.handled;
    }
    if (isCtrl && isShift && event.logicalKey == LogicalKeyboardKey.keyM) {
      _handleMinimap();
      return KeyEventResult.handled;
    }
    if (isCtrl && isShift && event.logicalKey == LogicalKeyboardKey.keyU) {
      _handleToggleRoute();
      return KeyEventResult.handled;
    }
    if (isCtrl && isShift && event.logicalKey == LogicalKeyboardKey.keyP) {
      _handleCompanion();
      return KeyEventResult.handled;
    }
    if (isCtrl && isShift && event.logicalKey == LogicalKeyboardKey.keyH) {
      _handleHome();
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.f11) {
      _handleFocus();
      return KeyEventResult.handled;
    }
    // 导航: Alt+← 后退, Alt+→ 前进
    if (isAlt && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      ref.read(navigationControllerProvider.notifier).back();
      return KeyEventResult.handled;
    }
    if (isAlt && event.logicalKey == LogicalKeyboardKey.arrowRight) {
      ref.read(navigationControllerProvider.notifier).forward();
      return KeyEventResult.handled;
    }
    // 章节切换: 仅在编辑器路由且无修饰键时生效
    // 避免在 TextField 焦点中触发 — 单独字母键, 无 Ctrl/Alt/Shift
    if (!isCtrl &&
        !isShift &&
        !isAlt &&
        ref.read(appRouteProvider) == AppRoute.editor) {
      if (event.logicalKey == LogicalKeyboardKey.keyQ) {
        if (_navigateChapter(-1)) return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyE) {
        if (_navigateChapter(1)) return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// 切换到上一章 (delta=-1) / 下一章 (delta=+1)
  /// 仅当当前书与章节有效、目标索引在范围内时切换
  bool _navigateChapter(int delta) {
    final bookId = ref.read(currentBookProvider);
    final chapterId = ref.read(currentChapterProvider);
    if (bookId == null || chapterId == null) return false;
    final books = ref.read(booksProvider).asData?.value;
    if (books == null) return false;
    final book = books.where((b) => b.id == bookId).firstOrNull;
    if (book == null) return false;
    final chapters = book.chapters;
    final idx = chapters.indexWhere((c) => c.id == chapterId);
    if (idx < 0) return false;
    final next = idx + delta;
    if (next < 0 || next >= chapters.length) return false;
    ref.read(currentChapterProvider.notifier).state = chapters[next].id;
    return true;
  }

  void _handleSave() {
    // D22.2: 调用本地保存 (写 .md 文件, 不走 HTTP)
    saveCurrentChapter(ref);
  }

  void _handleSearch() {
    showDialog(context: context, builder: (_) => const SearchDialog());
  }

  void _handleMinimap() {
    final v = ref.read(showMinimapProvider.notifier);
    v.state = !v.state;
  }

  void _handleFocus() {
    ref.read(focusModeProvider.notifier).state = !ref.read(focusModeProvider);
  }

  void _handleCompanion() {
    // 切换伴随面板：复用 navigationController (companion <-> editor)
    final r = ref.read(appRouteProvider);
    ref
        .read(navigationControllerProvider.notifier)
        .push(r == AppRoute.companion ? AppRoute.editor : AppRoute.companion);
  }

  void _handleHome() {
    // 回到主页 (Dashboard) — 走导航历史栈
    ref.read(navigationControllerProvider.notifier).goHome();
  }

  void _handleToggleRoute() {
    final r = ref.read(appRouteProvider);
    ref
        .read(navigationControllerProvider.notifier)
        .push(r == AppRoute.editor ? AppRoute.project : AppRoute.editor);
  }

  @override
  Widget build(BuildContext context) {
    // Phase 1.7: 激活 prefs watchers (debounce 500ms 写盘)
    ref.watch(aiPanelWatcher);
    ref.watch(sidebarCollapseWatcher);
    // D37 Phase 3-4: themeMode / editorFontFamily 持久化 watcher
    ref.watch(themeModeWatcher);
    ref.watch(editorFontFamilyWatcher);
    // D40: selectedModel / aiContextStrategy 持久化 watcher
    ref.watch(selectedModelWatcher);
    ref.watch(aiContextStrategyWatcher);
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      // Listener: 捕获鼠标侧键 (按键 3/4) 切换章节
      // 按钮 0=左键, 1=中键, 2=右键, 3=X1 后退侧键, 4=X2 前进侧键
      child: Listener(
        onPointerDown: (event) {
          // 仅在编辑器路由处理侧键切章
          if (ref.read(appRouteProvider) != AppRoute.editor) return;
          if (event.buttons == 3) {
            // X1 后退键 → 上一章
            _navigateChapter(-1);
          } else if (event.buttons == 4) {
            // X2 前进键 → 下一章
            _navigateChapter(1);
          }
        },
        child: widget.child,
      ),
    );
  }
}
