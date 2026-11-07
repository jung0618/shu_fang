/// 主页滚动动态条 (D22 补全) — 定档记录 / 最近活动 / 系统公告
///
/// D37 Phase 3-3: 改 ConsumerStatefulWidget, 接入真实书籍+引擎状态
/// 抽离自 home_dashboard_page.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/home_dashboard_data.dart';
import '../store/editor_store.dart';
import '../theme/colors.dart';
import '../theme/motion.dart';
import '../theme/radius.dart';
import '../theme/spacing.dart';

// ============================================================
// 滚动动态条 (D22 补全) — 定档记录 / 最近活动 / 系统公告
// D37 Phase 3-3: 改 ConsumerStatefulWidget, 接入真实书籍+引擎状态
// ============================================================

class HomeNewsTicker extends ConsumerStatefulWidget {
  final Brightness brightness;
  const HomeNewsTicker({super.key, required this.brightness});

  @override
  ConsumerState<HomeNewsTicker> createState() => _HomeNewsTickerState();
}

class _HomeNewsTickerState extends ConsumerState<HomeNewsTicker> {
  // 性能优化 UI-2-7: 用 ValueNotifier 替代 setState, 避免 _NewsTicker 整体重建
  final ValueNotifier<int> _idxNotifier = ValueNotifier<int>(0);
  late final _scrollCtrl = ScrollController();

  /// D37 Phase 3-3: 基于真实数据生成 NewsItem
  /// 之前: 完全 mock ("连签3天"等假文案)
  /// 现在: 取最近修改的书籍 → 生成动态; 引擎状态实采; 通用引导项保留
  List<HomeNewsItem> _buildItems() {
    final items = <HomeNewsItem>[];
    final booksAsync = ref.read(homeBooksProvider);
    final books = booksAsync.valueOrNull ?? [];
    final engineReady = ref.read(engineReadyProvider);

    // 1. 最近修改的书籍 (真实)
    final sortedBooks = [...books]..sort((a, b) {
      final aTime = _parseLastEdited(a.lastEdited);
      final bTime = _parseLastEdited(b.lastEdited);
      return bTime.compareTo(aTime);
    });
    if (sortedBooks.isNotEmpty) {
      final latest = sortedBooks.first;
      final agoText = _formatTimeAgo(_parseLastEdited(latest.lastEdited));
      items.add(
        HomeNewsItem(
          latest.coverEmoji,
          '最近编辑: 《${latest.title}》$agoText, 共 ${latest.chapterCount} 章 ${_formatCount(latest.wordCount)} 字',
        ),
      );
    } else {
      items.add(const HomeNewsItem('📚', '还没有书籍, 点击左侧 + 创建第一本书'));
    }

    // 2. 引擎状态 (真实)
    if (engineReady) {
      items.add(const HomeNewsItem('⚙️', '写作引擎已连接，具体能力以功能页面状态为准'));
    } else {
      items.add(const HomeNewsItem('⚙️', '本机写作引擎未连接，仍可继续写作'));
    }

    // 3. 通用引导项 (保留少量 mock, 但去掉"连签3天"等假反馈)
    items.add(
      const HomeNewsItem('💡', '快捷键: Ctrl+S 保存, Ctrl+J 切换 AI 面板, F11 全屏'),
    );

    return items;
  }

  DateTime _parseLastEdited(String? s) {
    if (s == null || s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatTimeAgo(DateTime time) {
    if (time.millisecondsSinceEpoch == 0) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${time.month}/${time.day}';
  }

  // D37 Phase 3-3: 复用 _BookCard._formatCount 的字数格式化逻辑
  String _formatCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  @override
  void initState() {
    super.initState();
    _autoRotate();
  }

  void _autoRotate() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) break;
      // 性能优化: 只更新 ValueNotifier, 不调 setState
      final items = _buildItems();
      if (items.isEmpty) continue;
      _idxNotifier.value = (_idxNotifier.value + 1) % items.length;
    }
  }

  @override
  void dispose() {
    _idxNotifier.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(engineReadyProvider);
    // D37 Phase 3-3: 每次重建都重算 items, 因为依赖的 books/engine 状态可能变化
    final items = _buildItems();
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    // 性能优化: ValueListenableBuilder 只重建 AnimatedSwitcher 子树
    return ValueListenableBuilder<int>(
      valueListenable: _idxNotifier,
      builder: (context, idx, _) {
        final safeIdx = items.isEmpty ? 0 : idx % items.length;
        final item = items[safeIdx];
        return AnimatedSwitcher(
          duration: Motion.slow,
          transitionBuilder:
              (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
          // emoji 与文本分成两个独立卡片, 中间留 16px 间距
          child: Row(
            key: ValueKey(idx),
            children: [
              // emoji 卡片
              Container(
                padding: const EdgeInsets.all(S.sm),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Text(item.emoji, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: S.lg),
              // 文本卡片 (含计数器 pill)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(S.md),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.text,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppPalette.textSecondary(widget.brightness),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: S.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.textTertiary(
                            widget.brightness,
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(R.pill),
                        ),
                        child: Text(
                          '${safeIdx + 1}/${items.length}',
                          style: TextStyle(
                            fontSize: 9,
                            color: AppPalette.textTertiary(widget.brightness),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class HomeNewsItem {
  final String emoji;
  final String text;
  const HomeNewsItem(this.emoji, this.text);
}
