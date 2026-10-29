import 'dart:async';
import '../services/chapter_save_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart' show localDataSource;
import '../theme/theme.dart';
import '../widgets/chapter_sidebar.dart';
import '../widgets/toolbar.dart';
import '../widgets/status_bar.dart';
import '../widgets/minimap_dock.dart';
import '../widgets/multi_buffer_bar.dart';
import '../widgets/ai_context_panel.dart';
import '../widgets/highlighted_text_editing_controller.dart';
import '../widgets/editor_context_menu.dart';
import '../theme/app_background.dart';
import '../utils/highlight_parser.dart';
import '../store/snippets_store.dart';

/// 编辑器主页面 — Toolbar + 编辑区 (_EditorBody) + StatusBar
class EditorPage extends ConsumerWidget {
  const EditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: AppBackground(
          child: Column(
            children: [
              const Toolbar(),
              const Expanded(child: _EditorBody()),
              const StatusBar(),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorBody extends ConsumerWidget {
  const _EditorBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focus = ref.watch(focusModeProvider);
    final activeBuffer = ref.watch(activeBufferProvider);
    final showAiPanel = ref.watch(showAiPanelProvider);
    final hasOpenBook = activeBuffer != null;
    final splitBuffer = ref.watch(splitBufferProvider);
    final isSplit =
        activeBuffer != null &&
        splitBuffer != null &&
        splitBuffer.chapterId != activeBuffer.chapterId;

    return Container(
      color: AppPalette.scaffold(Theme.of(context).brightness),
      child: Row(
        children: [
          if (!focus) const ChapterSidebar(),
          Expanded(
            child: Column(
              children: [
                if (!focus) const MultiBufferBar(),
                Expanded(
                  child:
                      activeBuffer == null
                          ? Center(
                            child: EmptyState(
                              icon: Icons.bookmark_add_outlined,
                              title: '未打开任何章节',
                              subtitle: '从左侧章节树选择章节, 或按 Ctrl+Shift+H 回到主页',
                            ),
                          )
                          : isSplit
                          ? Row(
                            children: [
                              Expanded(
                                child: _ChapterEditor(
                                  book: activeBuffer.bookId,
                                  chapter: activeBuffer.chapterId,
                                ),
                              ),
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: AppPalette.divider(
                                  Theme.of(context).brightness,
                                ),
                              ),
                              Expanded(
                                child: _ChapterEditor(
                                  book: splitBuffer.bookId,
                                  chapter: splitBuffer.chapterId,
                                  isSplit: true,
                                ),
                              ),
                            ],
                          )
                          : _ChapterEditor(
                            book: activeBuffer.bookId,
                            chapter: activeBuffer.chapterId,
                          ),
                ),
              ],
            ),
          ),
          if (showAiPanel && !focus) _AiPanelRail(hasOpenBook: hasOpenBook),
        ],
      ),
    );
  }
}

/// 右侧常驻 AI 面板容器
/// 打开书时显示 AiContextPanel, 未打开书时显示引导空状态
class _AiPanelRail extends StatelessWidget {
  final bool hasOpenBook;
  const _AiPanelRail({required this.hasOpenBook});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final windowWidth = MediaQuery.sizeOf(context).width;
    final panelWidth = (windowWidth * 0.28).clamp(280.0, 320.0).toDouble();
    return Container(
      width: panelWidth,
      decoration: BoxDecoration(
        color: AppPalette.surface(b),
        border: Border(
          left: BorderSide(color: AppPalette.divider(b), width: 1),
        ),
      ),
      child: hasOpenBook ? const AiContextPanel() : _AiEmptyState(),
    );
  }
}

/// AI 面板未打开书时的引导空状态
class _AiEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 48,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 12),
          const Text('AI 功能'),
          const SizedBox(height: 4),
          Text(
            '打开一本书后即可使用 AI 续写 / 改写 / 上下文检索',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).disabledColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ChapterEditor extends ConsumerStatefulWidget {
  final String? chapter;
  final String? book;
  final bool isSplit;

  const _ChapterEditor({
    required this.chapter,
    required this.book,
    this.isSplit = false,
  });

  @override
  ConsumerState<_ChapterEditor> createState() => _ChapterEditorState();
}

class _ChapterEditorState extends ConsumerState<_ChapterEditor> {
  final ScrollController _scrollController = ScrollController();

  // T-14: 已加载高亮的章节 key, 避免重复加载
  String? _highlightsLoadedKey;
  int _highlightsReadVersion = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// D50: 检测章节切换, 清理跨章残留状态 (高亮/相同词等)
  /// _ChapterEditor 用 key: 'editor-persistent' 跨章复用同一 State 实例,
  /// 必须在此主动检测 book/chapter 变化并清理, 否则旧章状态会污染新章
  @override
  void didUpdateWidget(covariant _ChapterEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bookChanged = oldWidget.book != widget.book;
    final chapterChanged = oldWidget.chapter != widget.chapter;
    if (bookChanged || chapterChanged) {
      _highlightsLoadedKey = null;
      _highlightsReadVersion++;
      final book = widget.book;
      final chapter = widget.chapter;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.book != book || widget.chapter != chapter) {
          return;
        }
        _clearChapterScopedState();
        ref.read(scrollOffsetProvider.notifier).state = 0.0;
        ref.read(viewportRangeProvider.notifier).state = const ViewportRange(
          firstLine: 0,
          lastLine: 0,
        );
      });
    }
  }

  /// D50: 章节切换时清理跨章残留状态
  /// 主章路径专用 — 清空全局 highlightsProvider / sameWordHighlightsProvider /
  /// activeHighlightColorProvider, 重置 _highlightsLoadedKey, 强制下次重新加载
  void _clearChapterScopedState() {
    if (widget.isSplit) return; // 分屏章不操作全局 provider
    ref.read(highlightsProvider.notifier).state = [];
    ref.read(sameWordHighlightsProvider.notifier).state = [];
    ref.read(activeHighlightColorProvider.notifier).state = null;
    // D50-4 (M6): 清空待插入文本, 避免旧章 pendingInsert 注入新章
    ref.read(pendingInsertProvider.notifier).state = null;
    ref.read(pendingChapterRestoreProvider.notifier).state = null;
    // D50-7 (M4): 清空 editorTextProvider, 避免旧章字数触发里程碑鼓励气泡
    ref.read(editorTextProvider.notifier).state = '';
    // D50-10 (L3): 清空旧章审阅结果, 避免新章误展示
    ref.read(reviewResultProvider.notifier).state = null;
    ref.read(activeReviewQuestionsProvider.notifier).state = [];
  }

  /// T-14: 加载章节荧光笔高亮 (持久化)
  /// 仅主章加载 (分屏章共享全局 highlightsProvider, 不覆盖)
  /// 章节切换时调用, 读取 .highlight.json 填充 highlightsProvider
  Future<void> _loadHighlights(String bookId, String chapterId) async {
    if (widget.isSplit) return; // 分屏章不加载
    final key = '$bookId:$chapterId';
    if (_highlightsLoadedKey == key) return; // 已加载, 不重复
    _highlightsLoadedKey = key;
    final readVersion = ++_highlightsReadVersion;
    await Future<void>.delayed(Duration.zero);
    if (!mounted ||
        readVersion != _highlightsReadVersion ||
        widget.book != bookId ||
        widget.chapter != chapterId) {
      return;
    }
    // D50: 立即清空旧章高亮, 避免新章文本上画旧章高亮 (异步加载期间残留)
    ref.read(highlightsProvider.notifier).state = [];
    try {
      final rawList = await localDataSource.readHighlights(bookId, chapterId);
      if (!mounted || readVersion != _highlightsReadVersion) return;
      final marks =
          rawList
              .map((m) => HighlightMark.fromJson(m))
              .where((m) => m.id.isNotEmpty)
              .toList();
      // 仅当当前章节仍是目标章节时才填充 (避免异步竞态)
      final currentBook = ref.read(currentBookProvider);
      final currentChapter = ref.read(currentChapterProvider);
      if (currentBook == bookId && currentChapter == chapterId) {
        ref.read(highlightsProvider.notifier).state = marks;
      }
    } catch (_) {
      // 加载失败静默处理
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    ref.listen(pendingChapterRestoreProvider, (_, next) {
      if (!widget.isSplit &&
          next != null &&
          next.address.root == localDataSource.storageRoot &&
          next.address.book == widget.book &&
          next.address.chapter == widget.chapter) {
        // A delayed annotation read must not reapply offsets from before the
        // restored text replaced this document.
        _highlightsReadVersion++;
      }
    });
    if (widget.chapter == null || widget.book == null) {
      return Center(
        child: EmptyState(
          icon: Icons.edit_note_rounded,
          title: widget.book == null ? '请选择一本书' : '请选择一章',
          subtitle: widget.book == null ? '在左侧侧边栏选择书籍开始写作' : '从左侧展开书籍并选择章节',
        ),
      );
    }

    final chapterKey = '${widget.book}:${widget.chapter}';
    final root = ref.watch(storageRootProvider);
    final contentAsync = ref.watch(chapterContentProvider(chapterKey));
    final draft = chapterSaveQueue.draftFor(
      ChapterAddress(root, widget.book!, widget.chapter!),
    );
    final displayText = draft ?? contentAsync.valueOrNull ?? '';
    final showInitialLoading = contentAsync.isLoading && draft == null;
    if (contentAsync.hasValue && !widget.isSplit) {
      _loadHighlights(widget.book!, widget.chapter!);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.xxl, vertical: S.lg),
      child: Row(
        children: [
          // 写作卡片设置最大阅读宽度，避免桌面宽屏下正文行过长。
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: AppCard(
                  padding: EdgeInsets.zero,
                  radius: R.md,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 章节标题
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: S.xxl,
                          vertical: S.lg,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: AppPalette.divider(b),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                (widget.isSplit
                                        ? ref.watch(splitChapterTitleProvider)
                                        : ref.watch(
                                          currentChapterTitleProvider,
                                        )) ??
                                    '',
                                style:
                                    Theme.of(context).textTheme.headlineMedium,
                              ),
                            ),
                            // 分屏章显示关闭按钮, 主章显示保存状态
                            if (widget.isSplit)
                              _SplitCloseButton()
                            else
                              _SaveStatusChip(),
                          ],
                        ),
                      ),
                      // 主体
                      Expanded(
                        child:
                            showInitialLoading
                                ? const Center(
                                  child: CircularProgressIndicator(),
                                )
                                : (contentAsync.hasError && draft == null
                                    ? Center(
                                      child: Text(
                                        '加载失败: ${contentAsync.error}',
                                      ),
                                    )
                                    : _EditorTextField(
                                      key: ValueKey(
                                        '$root:$chapterKey:${widget.isSplit}',
                                      ),
                                      initialText: displayText,
                                      scrollController: _scrollController,
                                      isSplit: widget.isSplit,
                                      saveBook: widget.book,
                                      saveChapter: widget.chapter,
                                    )),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Minimap 停靠 (Phase 1.6: 从浮层改为右侧固定停靠, 含 × 关闭 + 右键"不在本书展示")
          // 分屏章不显示 (isSplit), loading 期间不显示 (避免闪烁)
          if (!widget.isSplit && !showInitialLoading)
            MinimapDock(text: displayText, scrollController: _scrollController),
        ],
      ),
    );
  }
}

/// 分屏章关闭按钮 — 点击清除 splitChapterProvider
class _SplitCloseButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    return Tooltip(
      message: '关闭分屏',
      child: InkWell(
        onTap: () => ref.read(splitChapterProvider.notifier).state = null,
        borderRadius: BorderRadius.circular(R.sm),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.close, size: 16, color: AppPalette.textTertiary(b)),
        ),
      ),
    );
  }
}

class _SaveStatusChip extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(saveStatusProvider);
    final (icon, text, color) = switch (status) {
      SaveStatus.idle => (
        Icons.check_circle_outline_rounded,
        '就绪',
        AppPalette.textTertiary(Theme.of(context).brightness),
      ),
      SaveStatus.unsaved => (
        Icons.edit_outlined,
        '待保存',
        Theme.of(context).colorScheme.primary,
      ),
      SaveStatus.saving => (
        Icons.sync_rounded,
        '保存中…',
        Theme.of(context).colorScheme.primary,
      ),
      SaveStatus.saved => (
        Icons.check_circle_rounded,
        '已保存',
        AppColors.success,
      ),
      SaveStatus.error => (
        Icons.error_outline_rounded,
        '保存失败',
        AppColors.error,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _EditorTextField extends ConsumerStatefulWidget {
  final String initialText;
  final ScrollController scrollController;
  final bool isSplit;
  final String? saveBook;
  final String? saveChapter;
  const _EditorTextField({
    super.key,
    required this.initialText,
    required this.scrollController,
    this.isSplit = false,
    this.saveBook,
    this.saveChapter,
  });

  @override
  ConsumerState<_EditorTextField> createState() => _EditorTextFieldState();
}

class _EditorTextFieldState extends ConsumerState<_EditorTextField> {
  late final HighlightedTextEditingController _ctrl;
  late final UndoHistoryController _undoCtrl;
  late final FocusNode _focus;
  late final ChapterAddress _address;
  List<Map<String, dynamic>>? _pendingHighlights;
  // T-14: 高亮持久化防抖 timer (1 秒无变化后写盘)
  Timer? _highlightSaveTimer;

  // Ctrl+1/2/3 快捷高亮映射 (黄/红/蓝)
  static const _shortcutColors = [
    HighlightColor.yellow,
    HighlightColor.red,
    HighlightColor.blue,
  ];

  @override
  void initState() {
    super.initState();
    _address = ChapterAddress(
      localDataSource.storageRoot,
      widget.saveBook!,
      widget.saveChapter!,
    );
    chapterSaveQueue.registerFlusher(this, _flushHighlights);
    // 用高亮感知 controller: buildTextSpan 会按 highlights 渲染背景色
    _ctrl = HighlightedTextEditingController(text: widget.initialText);
    // D50: 每个 _EditorTextField 自建 UndoHistoryController, 避免跨章共享撤销历史
    // (之前用全局 editorUndoControllerProvider, 章节B按Ctrl+Z会撤销章节A的编辑)
    _undoCtrl = UndoHistoryController();
    // D50: 主章注册到全局 provider, 让 toolbar/Ctrl+Z 能找到当前激活的 controller
    // 分屏章不注册 (避免覆盖主章的 undo 状态)
    if (!widget.isSplit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(editorUndoControllerProvider.notifier).state = _undoCtrl;
          ref.read(editorControllerProvider.notifier).state = (
            address: _address,
            controller: _ctrl,
          );
        }
      });
    }
    // FocusNode 绑定 onKeyEvent: 处理 Ctrl+1/2/3 快捷高亮
    _focus = FocusNode(onKeyEvent: _handleKeyEvent);
    _focus.addListener(() {
      setState(() {});
    });
    // 初始同步一次高亮 (避免首次渲染无背景)
    // The new document's annotations load independently after this frame.
    // E 阶段: 初始化字数统计 (避免首次显示为 0)
    // 分屏章不更新全局字数 (那是主章的状态)
    if (!widget.isSplit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(editorTextProvider.notifier).state = _ctrl.text;
        setWordCount(ref, _ctrl.text);
      });
    }
    // 加载该书的预设片段 + 历史剪切板 (避免 recordClipboardHistory 用空列表覆盖磁盘)
    final book0 = widget.saveBook;
    if (book0 != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) loadSnippetsForBook(ref, book0);
      });
    }
  }

  /// 把 provider 中的高亮同步到 controller, 触发 buildTextSpan 重绘文本背景
  void _syncHighlights() {
    final h = ref.read(highlightsProvider);
    final hc = _ctrl;
    if (hc.highlights != h) {
      hc.highlights = h;
      // 通知 controller 重绘 (text 不变, 仅触发 buildTextSpan)
      hc.value = hc.value.copyWith(
        text: hc.text,
        selection: hc.selection,
        composing: hc.value.composing,
      );
    }
  }

  /// Ctrl+1/2/3 快捷高亮 — 选中文本后直接按快捷键上色
  /// Ctrl+C / Ctrl+X — 记录到历史剪切板 (默认 copy/cut 行为由 TextField 处理)
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    if (!isCtrl) return KeyEventResult.ignored;

    final label = event.logicalKey.keyLabel;

    // Ctrl+C / Ctrl+X: 记录选中文本到历史剪切板 (fire-and-forget, 默认行为继续)
    if (label == 'C' || label == 'X') {
      final sel = _ctrl.selection;
      if (sel.isValid && sel.start != sel.end) {
        final text = _ctrl.text.substring(sel.start, sel.end);
        final book = widget.saveBook;
        if (book != null) {
          recordClipboardHistory(ref, book, text);
        }
      }
      return KeyEventResult.ignored;
    }

    int? colorIndex;
    if (label == '1') {
      colorIndex = 0;
    } else if (label == '2') {
      colorIndex = 1;
    } else if (label == '3') {
      colorIndex = 2;
    }
    if (colorIndex == null) return KeyEventResult.ignored;

    // 有选区时才应用高亮
    final sel = _ctrl.selection;
    if (!sel.isValid || sel.start == sel.end) return KeyEventResult.ignored;

    final selected = _ctrl.text.substring(sel.start, sel.end);
    _applyHighlight(_shortcutColors[colorIndex], sel.start, sel.end, selected);
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(covariant _EditorTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 书籍切换: 加载新书的片段库 + 历史剪切板 (loadSnippetsForBook 内部防重)
    if (oldWidget.saveBook != widget.saveBook && widget.saveBook != null) {
      loadSnippetsForBook(ref, widget.saveBook!);
    }
    // A provider refresh may contain an older on-disk revision. Drafts own
    // the text until their latest revision is persisted.
    if (oldWidget.initialText != widget.initialText &&
        chapterSaveQueue.draftFor(_address) == null) {
      _ctrl.text = widget.initialText;
      if (!widget.isSplit) setWordCount(ref, widget.initialText);
    }
  }

  @override
  void dispose() {
    chapterSaveQueue.flush(_address);
    if (!widget.isSplit) cancelWordCountDebounce();
    _highlightSaveTimer?.cancel();
    _flushHighlights().then((ok) {
      if (ok) chapterSaveQueue.unregisterFlusher(this);
    });
    final undo = ref.read(editorUndoControllerProvider.notifier);
    final editor = ref.read(editorControllerProvider.notifier);
    scheduleMicrotask(() {
      if (undo.mounted && undo.state == _undoCtrl) undo.state = null;
      if (editor.mounted && editor.state?.controller == _ctrl) {
        editor.state = null;
      }
    });
    _ctrl.dispose();
    _undoCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// T-14: 立即写入当前高亮到 .highlight.json (仅主章)
  Future<bool> _flushHighlights() async {
    final snapshot = _pendingHighlights;
    if (widget.isSplit || snapshot == null) return true;
    final ok = await localDataSource.writeHighlights(
      _address.book,
      _address.chapter,
      snapshot,
      rootOverride: _address.root,
    );
    if (ok && identical(_pendingHighlights, snapshot)) {
      _pendingHighlights = null;
    }
    return ok;
  }

  void _scheduleSaveHighlights() {
    if (widget.isSplit) return;
    // Capture annotations here; disposal may run after selection has changed.
    if (ref.read(currentBookProvider) != _address.book ||
        ref.read(currentChapterProvider) != _address.chapter) {
      return;
    }
    _pendingHighlights =
        ref.read(highlightsProvider).map((mark) => mark.toJson()).toList();
    _highlightSaveTimer?.cancel();
    _highlightSaveTimer = Timer(const Duration(seconds: 1), _flushHighlights);
  }

  void _scheduleAutoSave() {
    chapterSaveQueue.stage(_address, _ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final font = ref.watch(editorFontFamilyProvider);
    // D50: 分屏章不监听/不操作全局 highlightsProvider, 避免污染主章
    // (分屏章高亮不持久化, 仅作只读参考)
    if (!widget.isSplit) {
      // 监听高亮变化, 同步到 controller 触发文本背景重绘
      // T-14: 同时触发 debounce 持久化到 .highlight.json
      ref.listen(highlightsProvider, (_, __) {
        _syncHighlights();
        _scheduleSaveHighlights();
      });
    }
    // T-2: 消费 pendingInsertProvider — AI 面板/inspire 页设置待插入文本, 编辑器自动插入到光标位置
    // 分屏章不消费 (避免插入到参考章)
    ref.listen(pendingInsertProvider, (_, next) {
      if (next == null || next.isEmpty) return;
      if (widget.isSplit) return;
      _insertAtCursor(next);
      ref.read(pendingInsertProvider.notifier).state = null;
    });
    ref.listen(pendingChapterRestoreProvider, (_, next) {
      if (next == null || next.address != _address || widget.isSplit) return;
      _ctrl.value = TextEditingValue(
        text: next.text,
        selection: const TextSelection.collapsed(offset: 0),
      );
      // Annotation offsets refer to the replaced text, so discard them rather
      // than rendering marks against unrelated positions in the restored text.
      ref.read(highlightsProvider.notifier).state = [];
      ref.read(sameWordHighlightsProvider.notifier).state = [];
      ref.read(reviewResultProvider.notifier).state = null;
      ref.read(activeReviewQuestionsProvider.notifier).state = [];
      ref.read(editorTextProvider.notifier).state = next.text;
      updateWordCountDebounced(ref, next.text);
      _scheduleAutoSave();
      ref.read(pendingChapterRestoreProvider.notifier).state = null;
    });
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.xxl, vertical: S.lg),
      child: TextField(
        controller: _ctrl,
        undoController: _undoCtrl,
        focusNode: _focus,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          fontFamily: font ?? 'serif',
          fontSize: 16,
          height: 1.8,
          color: AppPalette.textPrimary(Theme.of(context).brightness),
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isCollapsed: true,
          filled: false,
          contentPadding: EdgeInsets.zero,
          hintText: '开始你的故事...',
        ),
        onChanged: (v) {
          // 分屏章不更新全局 editorTextProvider / word count (那些属于主章)
          if (!widget.isSplit) {
            ref.read(editorTextProvider.notifier).state = v;
            // E 阶段: 字数统计防抖 500ms (避免每次按键重算)
            updateWordCountDebounced(ref, v);
          }
          _scheduleAutoSave(); // D22.2: 自动保存
        },
        // 右键菜单 — 复制/剪切/粘贴/高亮 + 预设片段库 (默认展示) + 历史剪切板 (点击展开)
        // Ctrl+1/2/3 快捷键映射黄/红/蓝 (在 _handleKeyEvent 中处理)
        // Ctrl+C/Ctrl+X 自动记录到历史剪切板 (在 _handleKeyEvent 中处理)
        contextMenuBuilder: (context, editableTextState) {
          return AdaptiveTextSelectionToolbar(
            anchors: editableTextState.contextMenuAnchors,
            children: [
              EditorContextMenu(
                editableTextState: editableTextState,
                controller: _ctrl,
                bookId: widget.saveBook,
                onHighlight: _applyHighlight,
              ),
            ],
          );
        },
      ),
    );
  }

  void _applyHighlight(
    HighlightColor color,
    int start,
    int end,
    String selected,
  ) {
    // D50: 分屏章不操作全局 highlightsProvider, 避免污染主章持久化
    if (widget.isSplit) return;
    final highlights = [...ref.read(highlightsProvider)];
    highlights.add(
      HighlightMark(
        id: 'hl-${DateTime.now().microsecondsSinceEpoch}',
        color: color,
        startOffset: start,
        endOffset: end,
        label:
            selected.length > 12 ? '${selected.substring(0, 12)}…' : selected,
      ),
    );
    ref.read(highlightsProvider.notifier).state = highlights;
    // 同步激活色 — 联动相同词
    ref.read(activeHighlightColorProvider.notifier).state = color;
    // 性能优化 UI-2-2: 大文本时走 Isolate 异步扫描, 避免阻塞主线程
    // 先显示主高亮, 相同词扫描完成后异步追加
    ref.read(sameWordHighlightsProvider.notifier).state = [];
    HighlightParser.findSameWordsAsync(_ctrl.text, selected).then((sameWords) {
      if (!mounted) return; // widget 已销毁则丢弃
      final currentHighlights = [...ref.read(highlightsProvider)];
      // 移除之前的 same- 前缀高亮, 避免重复
      currentHighlights.removeWhere((h) => h.id.startsWith('hl-same-'));
      final extended = [
        ...currentHighlights,
        ...sameWords.map(
          (m) => HighlightMark(
            id: 'hl-same-${m.startOffset}',
            color: color,
            startOffset: m.startOffset,
            endOffset: m.endOffset,
            label: m.word,
          ),
        ),
      ];
      ref.read(highlightsProvider.notifier).state = extended;
      ref.read(sameWordHighlightsProvider.notifier).state = sameWords;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已用${color.label}高亮 "${selected.length > 16 ? '${selected.substring(0, 16)}…' : selected}" (含 ${sameWords.length} 处相同词)',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  /// T-2: 把 AI 生成的文本插入到光标位置 (或末尾)
  /// 由 pendingInsertProvider 触发, 分屏章不消费
  void _insertAtCursor(String text) {
    final sel = _ctrl.selection;
    final insertPos = sel.isValid ? sel.end : _ctrl.text.length;
    final newText =
        _ctrl.text.substring(0, insertPos) +
        text +
        _ctrl.text.substring(insertPos);
    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: insertPos + text.length),
    );
    // 更新全局 editorTextProvider (主章)
    if (!widget.isSplit) {
      ref.read(editorTextProvider.notifier).state = newText;
      updateWordCountDebounced(ref, newText);
    }
    _scheduleAutoSave();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已插入 ${text.length} 字到光标位置'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }
}
