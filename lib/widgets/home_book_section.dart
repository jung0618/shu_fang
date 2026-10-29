/// 主页书籍选择卡片组 (抽离自 home_dashboard_page.dart)
///
/// 包含:
/// - HomeBookSection: 卡片网格区 (含新建按钮)
/// - HomeBookCard: 单本书卡片
/// - HomeNewBookCard: + 新建书籍卡片
/// - HomeNameBookDialog: 新建书籍名输入对话框
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/app_components.dart';
import '../pages/home_dashboard_data.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';
import '../store/local_prefs.dart' show PrefsController;
import '../theme/breakpoints.dart';
import '../theme/colors.dart';
import '../theme/radius.dart';
import '../theme/spacing.dart';

// ============================================================
// 书籍选择 (卡片网格)
// ============================================================

class HomeBookSection extends ConsumerWidget {
  final List<BookSummary> books;
  final Brightness brightness;
  const HomeBookSection({
    super.key,
    required this.books,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.menu_book_rounded,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: S.xs),
            Text('选择书籍', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed:
                  () =>
                      ref.read(appRouteProvider.notifier).state =
                          AppRoute.editor,
              icon: const Icon(Icons.edit_note, size: 16),
              label: const Text('进入编辑器'),
            ),
          ],
        ),
        const SizedBox(height: S.md),
        LayoutBuilder(
          builder: (context, constraints) {
            // T-24: 用断点系统决定列数, 响应窗口宽度
            final bp = AppBreakpoints.fromWidth(constraints.maxWidth);
            final crossAxisCount = switch (bp) {
              Breakpoint.narrow => 2,
              Breakpoint.medium => 3,
              Breakpoint.wide => math.max(
                4,
                (constraints.maxWidth / 240).floor().clamp(4, 6),
              ),
            };
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: S.md,
                crossAxisSpacing: S.md,
                childAspectRatio: 0.85,
              ),
              itemCount: books.length + 1, // +1 为新建
              itemBuilder: (context, i) {
                if (i < books.length) {
                  return HomeBookCard(book: books[i], brightness: brightness);
                }
                return const HomeNewBookCard();
              },
            );
          },
        ),
      ],
    );
  }
}

class HomeBookCard extends ConsumerWidget {
  final BookSummary book;
  final Brightness brightness;
  const HomeBookCard({super.key, required this.book, required this.brightness});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phase 3.3: 移除 DriftReveal (DriftReveal 仅用于主页快速入口条 emoji 按钮)
    // 书卡直接显示详情, 无悬停切换
    return AppCard(
      onTap: () async {
        final revision = localDataSource.sessionRevision;
        final root = ref.read(storageRootProvider);
        // D37 Phase 2-4 (P1-12): 书卡直开章节 — 自动打开首章
        // 之前只 set currentBook + 跳路由, 编辑器显示"未打开任何章节", 多两步
        // 现在: set book → 取章节列表 → 开首章 Buffer → 跳路由
        ref.read(currentBookProvider.notifier).state = book.id;
        // D37 Phase 3-5: 写入 lastOpenedBookId (跨会话记住, 主页排序用)
        PrefsController.update(
          PrefsController.current.copyWith(
            lastOpenedBooks: {
              ...PrefsController.current.lastOpenedBooks,
              root: book.id,
            },
          ),
        );
        try {
          final chapters = await localDataSource.listChapters(
            book.id,
            rootOverride: root,
          );
          if (!context.mounted || revision != localDataSource.sessionRevision) {
            return;
          }
          if (chapters.isNotEmpty) {
            final first = chapters.first;
            ref.read(currentChapterProvider.notifier).state = first.id;
            BufferActions.open(
              ref,
              bookId: book.id,
              chapterId: first.id,
              title: first.title,
            );
          }
        } catch (_) {
          // 取章节失败不阻塞跳转, 用户可手动从侧栏开章
        }
        if (!context.mounted || revision != localDataSource.sessionRevision) {
          return;
        }
        ref.read(appRouteProvider.notifier).state = AppRoute.editor;
      },
      padding: EdgeInsets.zero,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _coverGradient(book.id),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(R.md),
          ),
          padding: const EdgeInsets.all(S.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(book.coverEmoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      book.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${book.chapterCount} 章 · ${_formatCount(book.wordCount)} 字',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11,
                    ),
                  ),
                  if (book.lastEdited != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      book.lastEdited!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(R.pill),
                    child: LinearProgressIndicator(
                      value: book.progress,
                      minHeight: 3,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Color> _coverGradient(String id) {
    return BookCoverGradients.forId(id);
  }

  String _formatCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class HomeNewBookCard extends ConsumerWidget {
  const HomeNewBookCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      onTap: () => _createBook(context, ref),
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(
            color: AppPalette.divider(Theme.of(context).brightness),
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_circle_outline,
              size: 36,
              color: AppPalette.textTertiary(Theme.of(context).brightness),
            ),
            const SizedBox(height: S.xs),
            Text('新建书籍', style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }

  // D37 Phase 0-4: 主页"新建书籍"接通 (复用 LocalDataSource.createBook)
  Future<void> _createBook(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const HomeNameBookDialog(),
    );
    if (name == null || name.isEmpty) return;
    final ok = await localDataSource.createBook(name);
    if (ok) {
      ref.invalidate(booksProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已创建: $name'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('创建失败: 书籍可能已存在')));
    }
  }
}

/// 新建书籍名输入对话框 (D37 Phase 0-4)
class HomeNameBookDialog extends StatefulWidget {
  const HomeNameBookDialog({super.key});

  @override
  State<HomeNameBookDialog> createState() => _HomeNameBookDialogState();
}

class _HomeNameBookDialogState extends State<HomeNameBookDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建书籍'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: '书籍名',
          errorText: _errorText,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '书籍名不能为空');
      return;
    }
    if (RegExp(r'[\\/:*?"<>|]').hasMatch(name)) {
      setState(() => _errorText = '不能包含 \\ / : * ? " < > |');
      return;
    }
    Navigator.pop(context, name);
  }
}
