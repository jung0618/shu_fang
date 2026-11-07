import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../store/book_manifest_provider.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';
import '../theme/theme.dart';
import 'batch_import_dialog.dart';
import 'book_settings_dialog.dart';

/// 侧边栏：书-章 树 + 底部导航
class SidebarTree extends ConsumerStatefulWidget {
  const SidebarTree({super.key});

  @override
  ConsumerState<SidebarTree> createState() => _SidebarTreeState();
}

class _SidebarTreeState extends ConsumerState<SidebarTree> {
  final Set<String> _expandedBooks = {};

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final booksAsync = ref.watch(booksProvider);
    final currentBook = ref.watch(currentBookProvider);
    final currentChapter = ref.watch(currentChapterProvider);
    final contextAsync = ref.watch(unitrefContextProvider);
    final contextSize = contextAsync.asData?.value?['approx_chars'] as int?;

    return Container(
      // 磁吸侧边栏内自适应宽度, 不再固定 268
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppPalette.surface(b),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头部：标题 + 工具
          _Header(
            onCreateBook: () => _createBook(context),
            onBatchImport: currentBook == null
                ? null
                : () => _batchImport(context, currentBook),
            onRefresh: () => ref.invalidate(booksProvider),
          ),
          // 分割线
          Divider(height: 1, color: AppPalette.divider(b)),
          // 书籍列表
          Expanded(
            child: booksAsync.when(
              data: (books) {
                if (books.isEmpty) {
                  return EmptyState(
                    icon: Icons.menu_book_rounded,
                    title: '还没有书籍',
                    subtitle: '点击右上角 + 创建第一本书',
                    actionLabel: '新建书籍',
                    onAction: () => _createBook(context),
                  );
                }
                // 性能优化: 扁平化为 List 后用 ListView.builder 懒渲染
                // 大量章节时只构建可见行, 避免一次性构建所有 _BookTile/_ChapterTile
                final flat = _flattenBooks(books);
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: S.xs),
                  itemCount: flat.length,
                  itemBuilder: (context, i) {
                    final item = flat[i];
                    switch (item.kind) {
                      case _FlatKind.book:
                        final bk = item.book!;
                        return _BookTile(
                          book: bk,
                          expanded: _expandedBooks.contains(bk.id),
                          onToggle: () => setState(() {
                            if (_expandedBooks.contains(bk.id)) {
                              _expandedBooks.remove(bk.id);
                            } else {
                              _expandedBooks.add(bk.id);
                            }
                          }),
                          onSelect: () {
                            ref.read(currentBookProvider.notifier).state = bk.id;
                            ref.read(currentChapterProvider.notifier).state = null;
                          },
                          isCurrent: bk.id == currentBook,
                          currentChapter: currentChapter,
                          onChapterSelect: (cid) {
                            ref.read(currentBookProvider.notifier).state = bk.id;
                            ref.read(currentChapterProvider.notifier).state = cid;
                          },
                          onAddChapter: () => _addChapter(context, bk.id),
                        );
                      case _FlatKind.chapter:
                        final bk = item.book!;
                        final c = item.chapter!;
                        // D26 #1: 传 index 给 _ChapterTile, 用于条形格 (奇偶行交替底色)
                        // chapter 行在整列中的位置 = 当前 i 减去 book 行 + 此书内已展开的章节位置
                        return _ChapterTile(
                          chapter: c,
                          isCurrent: c.id == currentChapter,
                          index: item.chapterIndex,
                          bookId: bk.id,
                          onTap: () {
                            ref.read(currentBookProvider.notifier).state = bk.id;
                            ref.read(currentChapterProvider.notifier).state = c.id;
                            // 单击即打开编辑器 (不再需要双击)
                            ref.read(appRouteProvider.notifier).state = AppRoute.editor;
                            BufferActions.open(
                              ref,
                              bookId: bk.id,
                              chapterId: c.id,
                              title: c.title,
                            );
                          },
                          onDoubleTap: () {
                            ref.read(currentBookProvider.notifier).state = bk.id;
                            ref.read(currentChapterProvider.notifier).state = c.id;
                            ref.read(appRouteProvider.notifier).state = AppRoute.editor;
                            BufferActions.open(
                              ref,
                              bookId: bk.id,
                              chapterId: c.id,
                              title: c.title,
                            );
                          },
                        );
                      case _FlatKind.addChapter:
                        final bk = item.book!;
                        return InkWell(
                          onTap: () => _addChapter(context, bk.id),
                          child: Container(
                            height: 28,
                            padding: const EdgeInsets.only(left: 36, right: S.md),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.add_rounded,
                                  size: 12,
                                  color: AppPalette.textTertiary(Theme.of(context).brightness),
                                ),
                                const SizedBox(width: S.xs),
                                Text(
                                  '新章节',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: AppPalette.textTertiary(Theme.of(context).brightness),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        );
                    }
                  },
                );
              },
              loading: () => const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (e, _) => ErrorStateView(
                title: '加载失败',
                message: '$e',
                onRetry: () => ref.invalidate(booksProvider),
              ),
            ),
          ),
          // 上下文指示已内联 (Task 1.4: _ContextIndicator / _BottomEntries 已移除)
          if (contextSize != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: S.lg, vertical: S.xs),
              child: Text(
                '上下文 $contextSize 字',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppPalette.textTertiary(b),
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _createBook(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _NameInputDialog(
        title: '新建书籍',
        label: '书籍名',
        actionLabel: '创建',
      ),
    );
    if (name == null || name.isEmpty) return;
    final ok = await localDataSource.createBook(name);
    if (ok) {
      ref.invalidate(booksProvider);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建失败: 书籍可能已存在')),
      );
    }
  }

  Future<void> _addChapter(BuildContext context, String bookId) async {
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => _NameInputDialog(
        title: '新建章节',
        label: '章节标题',
        actionLabel: '创建',
      ),
    );
    if (title == null || title.isEmpty) return;
    // 用标题做文件名 (去掉不安全字符)
    final chapterId = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final ok = await localDataSource.createChapter(bookId, chapterId, title: title);
    if (ok) {
      ref.invalidate(booksProvider);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建失败: 章节可能已存在')),
      );
    }
  }

  /// 批量导入章节
  Future<void> _batchImport(BuildContext context, String bookId) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => BatchImportDialog(bookId: bookId),
    );
    if (result != null && context.mounted) {
      final created = result['created'] as int? ?? 0;
      final skipped = result['skipped'] as int? ?? 0;
      final msg = skipped > 0
          ? '本地导入完成: 新建 $created 章, 跳过 $skipped 章 (已存在)'
          : '本地导入完成: 新建 $created 章';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      ref.invalidate(booksProvider);
    }
  }

  /// 扁平化书籍+章节为单一列表 (供 ListView.builder 使用)
  /// 展开的书籍: [book, chapter1, chapter2, ..., addChapter]
  /// 折叠的书籍: [book]
  /// D26 #1: chapter 携带 chapterIndex, 用于条形格 (奇偶行交替底色)
  List<_FlatItem> _flattenBooks(List<BookInfo> books) {
    final result = <_FlatItem>[];
    for (final bk in books) {
      result.add(_FlatItem(kind: _FlatKind.book, book: bk));
      if (_expandedBooks.contains(bk.id)) {
        var chapterIdx = 0;
        for (final c in bk.chapters) {
          result.add(_FlatItem(
            kind: _FlatKind.chapter,
            book: bk,
            chapter: c,
            chapterIndex: chapterIdx,
          ));
          chapterIdx++;
        }
        result.add(_FlatItem(kind: _FlatKind.addChapter, book: bk));
      }
    }
    return result;
  }
}

/// 扁平化列表项类型
enum _FlatKind { book, chapter, addChapter }

class _FlatItem {
  final _FlatKind kind;
  final BookInfo? book;
  final ChapterInfo? chapter;
  /// D26 #1: 章在书内的索引 (0-based), 用于条形格交替
  final int chapterIndex;
  const _FlatItem({
    required this.kind,
    this.book,
    this.chapter,
    this.chapterIndex = 0,
  });
}

class _Header extends ConsumerWidget {
  final VoidCallback onCreateBook;
  final VoidCallback? onBatchImport;
  final VoidCallback onRefresh;

  const _Header({
    required this.onCreateBook,
    required this.onBatchImport,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    // T-19/T-22: minimap 恢复入口 (per-book 隐藏 或 会话级关闭 时显示)
    final hiddenForBook = ref.watch(isMinimapHiddenForCurrentBookProvider);
    final showMinimap = ref.watch(showMinimapProvider);
    final minimapHidden = hiddenForBook || !showMinimap;
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.sm, S.md),
      child: Row(
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 16,
            color: AppPalette.textSecondary(b),
          ),
          const SizedBox(width: S.sm),
          Text(
            '书籍与章节',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Spacer(),
          // T-19/T-22: minimap 被关闭时显示恢复按钮
          if (minimapHidden)
            ToolbarIconButton(
              icon: Icons.view_sidebar_outlined,
              tooltip: hiddenForBook
                  ? '在本书显示 Minimap (已按书隐藏)'
                  : '显示 Minimap (本次会话已关闭)',
              size: 28,
              iconSize: 14,
              onPressed: () async {
                if (hiddenForBook) {
                  // T-19: 恢复 per-book 隐藏
                  await setMinimapHiddenForCurrentBook(ref, false);
                }
                if (!showMinimap) {
                  // T-22: 恢复会话级关闭
                  ref.read(showMinimapProvider.notifier).state = true;
                }
              },
            ),
          ToolbarIconButton(
            icon: Icons.add_rounded,
            tooltip: '新建书籍',
            size: 28,
            iconSize: 14,
            onPressed: onCreateBook,
          ),
          ToolbarIconButton(
            icon: Icons.create_new_folder_outlined,
            tooltip: '批量导入章节',
            size: 28,
            iconSize: 14,
            onPressed: onBatchImport,
          ),
          ToolbarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: '刷新',
            size: 28,
            iconSize: 14,
            onPressed: onRefresh,
          ),
          // Task 1.4: 收起按钮 — 章节树可收起为 4px hover 触发条
          ToolbarIconButton(
            icon: Icons.chevron_left_rounded,
            tooltip: '收起章节树',
            size: 28,
            iconSize: 14,
            onPressed: () {
              ref.read(sidebarCollapsedProvider.notifier).state = true;
            },
          ),
        ],
      ),
    );
  }
}

// T-23: _SmallIconButton 已移除, 统一用 ToolbarIconButton (size: 28, iconSize: 14)

// _ContextIndicator 已移除 (Task 1.4: 上下文信息内联到 SidebarTree build, 不再独立组件)

class _BookTile extends ConsumerWidget {
  final BookInfo book;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onSelect;
  final bool isCurrent;
  final String? currentChapter;
  final ValueChanged<String> onChapterSelect;
  final VoidCallback onAddChapter;

  const _BookTile({
    required this.book,
    required this.expanded,
    required this.onToggle,
    required this.onSelect,
    required this.isCurrent,
    required this.currentChapter,
    required this.onChapterSelect,
    required this.onAddChapter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    // 性能优化: _BookTile 只渲染书籍标题行, 章节由扁平化 ListView.builder 单独渲染
    return InkWell(
      onTap: () {
        onSelect();
        onToggle();
      },
      onSecondaryTapDown: (d) => _showBookMenu(context, ref, d),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: S.md),
        color: isCurrent
            ? Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.6)
            : null,
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: Motion.fast,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: AppPalette.textTertiary(b),
              ),
            ),
            const SizedBox(width: S.xs),
            Icon(
              Icons.book_rounded,
              size: 14,
              color: isCurrent
                  ? Theme.of(context).colorScheme.primary
                  : AppPalette.textSecondary(b),
            ),
            const SizedBox(width: S.sm),
            Expanded(
              child: Text(
                book.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: isCurrent
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: AppPalette.surfaceHigh(b),
                borderRadius: BorderRadius.circular(R.pill),
              ),
              child: Text(
                '${book.chapters.length}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppPalette.textSecondary(b),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 右键弹出书籍上下文菜单 (目前仅含"书籍设置")
  Future<void> _showBookMenu(
    BuildContext context,
    WidgetRef ref,
    TapDownDetails details,
  ) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(value: 'settings', child: Text('书籍设置')),
        PopupMenuItem(value: 'addChapter', child: Text('新章节')),
        PopupMenuDivider(),
        // D37 Phase 2-5 (P1-8): 删除书籍
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: Color(0xFFC92A2A)),
              SizedBox(width: 8),
              Text('删除书籍'),
            ],
          ),
        ),
      ],
    );
    if (selected == 'settings' && context.mounted) {
      // 读现有 manifest 拿初始值 (不存在则用回退值)
      final manifest = await localDataSource.readBookManifest(book.id);
      if (!context.mounted) return;
      final initialTitle = (manifest['title'] ?? manifest['name'] ?? book.name).toString();
      final initialDesc = (manifest['desc'] ?? '').toString();
      final initialEmoji = (manifest['coverEmoji'] ?? '📖').toString();
      final result = await showDialog<bool>(
        context: context,
        builder: (_) => BookSettingsDialog(
          bookId: book.id,
          initialTitle: initialTitle,
          initialDescription: initialDesc,
          initialCoverEmoji: initialEmoji,
        ),
      );
      if (result == true) {
        ref.invalidate(booksProvider);
      }
    } else if (selected == 'addChapter') {
      onAddChapter();
    } else if (selected == 'delete' && context.mounted) {
      // D37 Phase 2-5 (P1-8): 删除书籍 (含确认对话框)
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除书籍'),
          content: Text(
            '确定要删除《${book.name}》吗?\n'
            '将删除所有章节、设定文件和 manifest, 此操作不可恢复。',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      final deleted = await localDataSource.deleteBook(book.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(deleted ? '已删除《${book.name}》' : '删除失败')),
      );
      if (deleted) {
        // 清理当前选中状态 (避免指向已删书)
        if (ref.read(currentBookProvider) == book.id) {
          ref.read(currentBookProvider.notifier).state = null;
          ref.read(currentChapterProvider.notifier).state = null;
        }
        ref.invalidate(booksProvider);
      }
    }
  }
}

class _ChapterTile extends ConsumerStatefulWidget {
  final ChapterInfo chapter;
  final bool isCurrent;
  final int index;
  final String bookId;  // D37 Phase 2-5 (P1-8): 删除章节需要 bookId
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  const _ChapterTile({
    required this.chapter,
    required this.isCurrent,
    required this.index,
    required this.bookId,
    required this.onTap,
    this.onDoubleTap,
  });

  @override
  ConsumerState<_ChapterTile> createState() => _ChapterTileState();
}

class _ChapterTileState extends ConsumerState<_ChapterTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    // D26 #1: 三层背景 - 当前章 (primaryContainer) > 悬停 (surfaceHigh) > 条形格 (奇偶行 4% alpha)
    final isEven = widget.index.isEven;
    final zebraColor = isEven
        ? Colors.transparent
        : AppPalette.divider(b).withValues(alpha: 0.12);
    final Color baseColor = widget.isCurrent
        ? Theme.of(context).colorScheme.primaryContainer
        : (_hovered ? AppPalette.surfaceHigh(b) : zebraColor);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        // D37 Phase 2-5 (P1-8): 章节右键菜单 — 删除章节
        onSecondaryTapDown: (d) => _showChapterMenu(context, d),
        child: AnimatedContainer(
          duration: Motion.micro,
          height: 30,
          padding: const EdgeInsets.only(left: 36, right: S.md),
          decoration: BoxDecoration(
            color: baseColor,
            // D26 #1: 选中态左侧加 3px 主色条, 强化"已选"视觉
            border: Border(
              left: BorderSide(
                color: widget.isCurrent
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.isCurrent
                    ? Icons.article_rounded
                    : Icons.article_outlined,
                size: 12,
                color: widget.isCurrent
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : AppPalette.textTertiary(b),
              ),
              const SizedBox(width: S.sm),
              Expanded(
                child: Text(
                  widget.chapter.title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: widget.isCurrent
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : AppPalette.textPrimary(b),
                        fontWeight: widget.isCurrent
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // D26 #1: 章节序号 (辅助定位, 1-based)
              if (widget.isCurrent)
                Text(
                  '#${widget.index + 1}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer
                            .withValues(alpha: 0.7),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// D37 Phase 2-5 (P1-8): 章节右键菜单 — 删除章节
  Future<void> _showChapterMenu(BuildContext context, TapDownDetails details) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: Color(0xFFC92A2A)),
              SizedBox(width: 8),
              Text('删除章节'),
            ],
          ),
        ),
      ],
    );
    if (selected != 'delete' || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除章节'),
        content: Text('确定要删除「${widget.chapter.title}」吗?\n此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await localDataSource.deleteChapter(widget.bookId, widget.chapter.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(deleted ? '已删除「${widget.chapter.title}」' : '删除失败')),
    );
    if (deleted) {
      // 清理当前选中章节 (若删的正是当前章)
      if (ref.read(currentChapterProvider) == widget.chapter.id) {
        ref.read(currentChapterProvider.notifier).state = null;
      }
      // D50-9 (L6): 若删的正是分屏章, 清空 splitChapterProvider
      if (ref.read(splitChapterProvider) == widget.chapter.id) {
        ref.read(splitChapterProvider.notifier).state = null;
      }
      // 失效该书的章节缓存
      invalidateChapterCache('${widget.bookId}:${widget.chapter.id}');
      ref.invalidate(booksProvider);
    }
  }
}

// _BottomEntries / _BottomEntry 已移除 (Task 1.4: 单元集/设定/AI/管理面板入口
// 移到对应工作区路由 project/review/preset, 不再出现在编辑器章节树底部)

/// 通用名称输入对话框
class _NameInputDialog extends StatefulWidget {
  final String title;
  final String label;
  final String actionLabel;

  const _NameInputDialog({
    required this.title,
    required this.label,
    required this.actionLabel,
  });

  @override
  State<_NameInputDialog> createState() => _NameInputDialogState();
}

class _NameInputDialogState extends State<_NameInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
