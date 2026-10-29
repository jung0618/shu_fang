/// 主页/仪表盘的数据模型与 Provider (抽离自 home_dashboard_page.dart)
///
/// 包含:
/// - WritingHeatmapData / BookSummary / LoreFilePreview (含 mock 工厂)
/// - homeBooksProvider / heatmapProvider / loreProvider
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../store/editor_store.dart';
import '../store/local_data_source.dart';
import '../store/local_prefs.dart' show PrefsController;

// ============================================================
// 数据模型 (mock, 后续接 API)
// ============================================================

/// 写作活动热力图数据 (近 N 天)
class WritingHeatmapData {
  final List<int> dailyWords; // dailyWords[i] = i 天前的字数
  final int totalDays;
  final int totalWords;

  const WritingHeatmapData({
    required this.dailyWords,
    required this.totalDays,
    required this.totalWords,
  });

  /// 从 mock 数据生成 (伪随机, 固定 seed)
  factory WritingHeatmapData.mock({int days = 365}) {
    final rng = math.Random(42); // 固定 seed, 保证稳定显示
    final list = List<int>.generate(days, (i) {
      // 70% 日子有活动, 30% 休息
      if (rng.nextDouble() < 0.3) return 0;
      // 字数 200-3500, 周末稍微多写
      final base = 200 + rng.nextInt(3300);
      return base;
    });
    final total = list.fold<int>(0, (a, b) => a + b);
    return WritingHeatmapData(
      dailyWords: list,
      totalDays: days,
      totalWords: total,
    );
  }

  /// 强度等级 0-4 (用于热力图着色)
  int intensityOf(int wordCount) {
    if (wordCount == 0) return 0;
    if (wordCount < 500) return 1;
    if (wordCount < 1200) return 2;
    if (wordCount < 2200) return 3;
    return 4;
  }
}

/// 书籍摘要 (卡片)
class BookSummary {
  final String id;
  final String title;
  final String coverEmoji;
  final int chapterCount;
  final int wordCount;
  final String? lastEdited;
  final double progress; // 0-1
  const BookSummary({
    required this.id,
    required this.title,
    required this.coverEmoji,
    required this.chapterCount,
    required this.wordCount,
    this.lastEdited,
    this.progress = 0.0,
  });

  static List<BookSummary> mock() => const [
    BookSummary(
      id: 'book1',
      title: '剑与星辰',
      coverEmoji: '⚔️',
      chapterCount: 42,
      wordCount: 124_000,
      lastEdited: '今天 14:30',
      progress: 0.72,
    ),
    BookSummary(
      id: 'book2',
      title: '深海回响',
      coverEmoji: '🌊',
      chapterCount: 18,
      wordCount: 56_000,
      lastEdited: '昨天 22:10',
      progress: 0.41,
    ),
    BookSummary(
      id: 'book3',
      title: '云端列车',
      coverEmoji: '🚂',
      chapterCount: 8,
      wordCount: 22_000,
      lastEdited: '3 天前',
      progress: 0.18,
    ),
  ];
}

/// 设定集文件 (近期)
class LoreFilePreview {
  final String name;
  final String path;
  final int sizeBytes;
  final String lastModified;
  const LoreFilePreview({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.lastModified,
  });

  static List<LoreFilePreview> mock() => const [
    LoreFilePreview(
      name: '主角设定.md',
      path: 'settings/主角设定.md',
      sizeBytes: 1200,
      lastModified: '2 天前',
    ),
    LoreFilePreview(
      name: '世界观.md',
      path: 'settings/世界观.md',
      sizeBytes: 3400,
      lastModified: '5 天前',
    ),
    LoreFilePreview(
      name: '伏笔追踪.md',
      path: 'settings/伏笔追踪.md',
      sizeBytes: 800,
      lastModified: '1 周前',
    ),
  ];
}

// ============================================================
// Provider (mock 数据, 后续可接 FutureProvider)
// ============================================================

// D37 Phase 3-2: 热力图接真实数据 (按日章节 mtime 估算字数)
// 之前: WritingHeatmapData.mock() 用 seed=42 伪随机, 永远显示同一组假数据
// 现在: 扫所有书的章节, 按 mtime 分组, 主页热力图反映真实写作活动
final heatmapProvider = FutureProvider<WritingHeatmapData>((ref) async {
  final root = ref.watch(storageRootProvider);
  // 依赖 booksProvider 触发刷新 (创建/删除书籍时热力图也刷新)
  await ref.watch(booksProvider.future);
  final dailyWords = await localDataSource.getDailyWordCounts(
    days: 365,
    rootOverride: root,
  );
  final total = dailyWords.fold<int>(0, (a, b) => a + b);
  return WritingHeatmapData(
    dailyWords: dailyWords,
    totalDays: 365,
    totalWords: total,
  );
});

// D37 Phase 3-1: 接入真实 booksProvider + getBookStats + manifest.coverEmoji
// 之前: wordCount=0 恒为 0, coverEmoji 恒为 📖 — 主页书卡全是假数据
// 现在: 并行读 manifest + getBookStats, 返回真实统计
final homeBooksProvider = FutureProvider<List<BookSummary>>((ref) async {
  final root = ref.watch(storageRootProvider);
  final lastOpened =
      PrefsController.current.lastOpenedBooks[root] ??
      (localDataSource.usesPrimaryStorage
          ? PrefsController.current.lastOpenedBookId
          : null);
  final books = await ref.watch(booksProvider.future);
  // D37 Phase 3-5: 按 lastOpenedBookId 排序 (最近打开在前)
  final sorted = [...books];
  sorted.sort((a, b) {
    if (a.id == b.id) return 0;
    if (a.id == lastOpened) return -1;
    if (b.id == lastOpened) return 1;
    return 0;
  });
  // 并行: 每本书都读 manifest + stats
  final summaries = await Future.wait(
    sorted.map((b) async {
      final manifest = await localDataSource.readBookManifest(
        b.id,
        rootOverride: root,
      );
      final stats = await localDataSource.getBookStats(
        b.id,
        chapters: b.chapters,
        rootOverride: root,
      );
      final cover = (manifest['coverEmoji'] as String?)?.trim();
      final coverEmoji = (cover != null && cover.isNotEmpty) ? cover : '📖';
      return BookSummary(
        id: b.id,
        title: b.name,
        coverEmoji: coverEmoji,
        chapterCount: stats.chapterCount,
        wordCount: stats.wordCount,
        // D37 Phase 3-1: lastEdited 存 ISO8601 字符串 (BookSummary.lastEdited 是 String?)
        lastEdited: stats.lastModified?.toIso8601String(),
        progress: 0.0,
      );
    }),
  );
  return summaries;
});

final loreProvider = Provider<List<LoreFilePreview>>((ref) {
  // Phase 3.2: 暂保留 mock, 后续接入真实 settingsFilesProvider
  return LoreFilePreview.mock();
});
