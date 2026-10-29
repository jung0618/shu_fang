// 预设片段库 + 历史剪切板状态管理 (per-book 持久化)
//
// 设计:
// - 每本书独立存储 (books/<bookId>/snippets.json + clipboard_history.json)
// - 预设片段: 用户手动添加的常用文本片段 (插入到光标)
// - 历史剪切板: 自动记录 Ctrl+C / Ctrl+X 的文本 (最多 50 条)
// - Provider 用 family 按 bookId 隔离, 切书自动加载
// - 写操作立即持久化到磁盘 (fire-and-forget, 不阻塞 UI)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_data_source.dart' show localDataSource;
import 'editor_store.dart' show storageRootProvider;

/// 预设片段
class PresetSnippet {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;

  const PresetSnippet({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'created_at': createdAt.toIso8601String(),
  };

  factory PresetSnippet.fromJson(Map<String, dynamic> j) => PresetSnippet(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    content: j['content'] as String? ?? '',
    createdAt:
        DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
  );

  PresetSnippet copyWith({String? title, String? content}) => PresetSnippet(
    id: id,
    title: title ?? this.title,
    content: content ?? this.content,
    createdAt: createdAt,
  );
}

/// 历史剪切板条目
class ClipboardEntry {
  final String id;
  final String content;
  final DateTime createdAt;

  const ClipboardEntry({
    required this.id,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'created_at': createdAt.toIso8601String(),
  };

  factory ClipboardEntry.fromJson(Map<String, dynamic> j) => ClipboardEntry(
    id: j['id'] as String? ?? '',
    content: j['content'] as String? ?? '',
    createdAt:
        DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
  );
}

/// 历史剪切板最大条数 (超出自动淘汰最早的)
const int kMaxClipboardHistory = 50;

// ============================================================
// Provider (family by bookId)
// ============================================================

/// 某本书的预设片段列表 (按 bookId 隔离)
/// 初始为空列表, 调用 loadSnippetsForBook() 异步加载
final presetSnippetsProvider =
    StateProvider.family<List<PresetSnippet>, String>((ref, bookId) {
      ref.watch(storageRootProvider);
      return const [];
    });

/// 某本书的历史剪切板 (按 bookId 隔离)
final clipboardHistoryProvider =
    StateProvider.family<List<ClipboardEntry>, String>((ref, bookId) {
      ref.watch(storageRootProvider);
      return const [];
    });

/// 标记某本书是否已加载过 (避免重复 IO)
final _loadedBooksProvider = StateProvider.family<bool, String>((ref, bookId) {
  ref.watch(storageRootProvider);
  return false;
});

// ============================================================
// 加载 (切书时调用)
// ============================================================

/// 从磁盘加载某本书的预设片段 + 历史剪切板 (如果尚未加载)
Future<void> loadSnippetsForBook(WidgetRef ref, String bookId) async {
  if (!ref.context.mounted) return;
  final revision = localDataSource.sessionRevision;
  if (ref.read(_loadedBooksProvider(bookId))) return;
  ref.read(_loadedBooksProvider(bookId).notifier).state = true;
  try {
    final results = await Future.wait([
      localDataSource.readSnippets(bookId),
      localDataSource.readClipboardHistory(bookId),
    ]);
    if (!ref.context.mounted || revision != localDataSource.sessionRevision) {
      return;
    }
    final snippets =
        (results[0] as List)
            .whereType<Map<String, dynamic>>()
            .map(PresetSnippet.fromJson)
            .toList();
    final history =
        (results[1] as List)
            .whereType<Map<String, dynamic>>()
            .map(ClipboardEntry.fromJson)
            .toList();
    ref.read(presetSnippetsProvider(bookId).notifier).state = snippets;
    ref.read(clipboardHistoryProvider(bookId).notifier).state = history;
  } catch (_) {
    if (ref.context.mounted && revision == localDataSource.sessionRevision) {
      ref.invalidate(_loadedBooksProvider(bookId));
    }
  }
}

/// 切换书籍时重置加载状态 (让下次切回时重新读盘)
void resetSnippetsLoadState(WidgetRef ref, String bookId) {
  ref.invalidate(_loadedBooksProvider(bookId));
}

// ============================================================
// 预设片段操作
// ============================================================

/// 添加预设片段
Future<void> addPresetSnippet(
  WidgetRef ref,
  String bookId,
  String title,
  String content,
) async {
  final list = [...ref.read(presetSnippetsProvider(bookId))];
  list.add(
    PresetSnippet(
      id: 'snip-${DateTime.now().microsecondsSinceEpoch}',
      title: title.isEmpty ? '未命名片段' : title,
      content: content,
      createdAt: DateTime.now(),
    ),
  );
  ref.read(presetSnippetsProvider(bookId).notifier).state = list;
  await localDataSource.writeSnippets(
    bookId,
    list.map((s) => s.toJson()).toList(),
  );
}

/// 更新预设片段
Future<void> updatePresetSnippet(
  WidgetRef ref,
  String bookId,
  String snippetId,
  String title,
  String content,
) async {
  final list = [...ref.read(presetSnippetsProvider(bookId))];
  final i = list.indexWhere((s) => s.id == snippetId);
  if (i < 0) return;
  list[i] = list[i].copyWith(
    title: title.isEmpty ? '未命名片段' : title,
    content: content,
  );
  ref.read(presetSnippetsProvider(bookId).notifier).state = list;
  await localDataSource.writeSnippets(
    bookId,
    list.map((s) => s.toJson()).toList(),
  );
}

/// 删除预设片段
Future<void> removePresetSnippet(
  WidgetRef ref,
  String bookId,
  String snippetId,
) async {
  final list = [...ref.read(presetSnippetsProvider(bookId))];
  list.removeWhere((s) => s.id == snippetId);
  ref.read(presetSnippetsProvider(bookId).notifier).state = list;
  await localDataSource.writeSnippets(
    bookId,
    list.map((s) => s.toJson()).toList(),
  );
}

// ============================================================
// 历史剪切板操作
// ============================================================

/// 记录一条剪切板历史 (Ctrl+C / Ctrl+X 触发)
/// - 去重: 与最近一条内容相同则跳过
/// - 截断: 超过 kMaxClipboardHistory 时丢弃最早的
/// - 截断内容: 超过 500 字符的条目只保留前 500 字 (避免巨型片段爆磁盘)
Future<void> recordClipboardHistory(
  WidgetRef ref,
  String bookId,
  String text,
) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return;
  final truncated =
      trimmed.length > 500 ? '${trimmed.substring(0, 500)}…' : trimmed;
  final list = [...ref.read(clipboardHistoryProvider(bookId))];
  // 去重: 与最近一条相同则跳过
  if (list.isNotEmpty && list.first.content == truncated) return;
  list.insert(
    0,
    ClipboardEntry(
      id: 'clip-${DateTime.now().microsecondsSinceEpoch}',
      content: truncated,
      createdAt: DateTime.now(),
    ),
  );
  // 截断到最大条数
  if (list.length > kMaxClipboardHistory) {
    list.removeRange(kMaxClipboardHistory, list.length);
  }
  ref.read(clipboardHistoryProvider(bookId).notifier).state = list;
  await localDataSource.writeClipboardHistory(
    bookId,
    list.map((e) => e.toJson()).toList(),
  );
}

/// 清空历史剪切板
Future<void> clearClipboardHistory(WidgetRef ref, String bookId) async {
  ref.read(clipboardHistoryProvider(bookId).notifier).state = const [];
  await localDataSource.writeClipboardHistory(bookId, const []);
}

/// 删除单条历史剪切板
Future<void> removeClipboardEntry(
  WidgetRef ref,
  String bookId,
  String entryId,
) async {
  final list = [...ref.read(clipboardHistoryProvider(bookId))];
  list.removeWhere((e) => e.id == entryId);
  ref.read(clipboardHistoryProvider(bookId).notifier).state = list;
  await localDataSource.writeClipboardHistory(
    bookId,
    list.map((e) => e.toJson()).toList(),
  );
}

void resetAllSnippets(WidgetRef ref) {
  ref.invalidate(presetSnippetsProvider);
  ref.invalidate(clipboardHistoryProvider);
  ref.invalidate(_loadedBooksProvider);
}
