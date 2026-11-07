// per-book manifest provider — 支撑 minimap "不在本书展示" 等持久化偏好
//
// 设计原则:
// - manifest.json 存储书籍级偏好 (hideMinimap, coverEmoji, lastChapter 等)
// - 与全局 user_prefs.json 互补: 全局偏好存 UI 通用状态, per-book 存书籍特定状态
// - FutureProvider.family 自动按 bookId 缓存, 写入后手动 invalidate

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'editor_store.dart' show currentBookProvider, storageRootProvider;
import 'local_data_source.dart' show localDataSource;

/// 当前书 manifest (FutureProvider.family 按 bookId 缓存)
///
/// 返回非空 Map (readBookManifest 在文件不存在/损坏时返回空 Map)
final bookManifestProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, bookId) async {
      ref.watch(storageRootProvider);
      return localDataSource.readBookManifest(bookId);
    });

/// 当前书的 minimap 是否被持久化隐藏 (per-book 偏好)
///
/// 优先级: per-book manifest.hideMinimap > 全局 showMinimapProvider
/// 使用方式: minimap 容器同时监听 showMinimapProvider (会话级) 和此 provider (持久级),
/// 任一为 true 则隐藏。当前实现: 仅当 manifest.hideMinimap == true 时返回 true.
final isMinimapHiddenForCurrentBookProvider = Provider<bool>((ref) {
  final bookId = ref.watch(currentBookProvider);
  if (bookId == null) return false;
  final asyncManifest = ref.watch(bookManifestProvider(bookId));
  return asyncManifest.whenOrNull(data: (m) => m['hideMinimap'] == true) ??
      false;
});

/// 设置当前书 minimap 隐藏偏好 (写入 manifest.json, 失效缓存)
///
/// 调用后 minimap 在本书内不再显示, 除非用户手动通过 minimap 菜单恢复.
Future<void> setMinimapHiddenForCurrentBook(WidgetRef ref, bool hidden) async {
  final bookId = ref.read(currentBookProvider);
  if (bookId == null) return;
  final root = ref.read(storageRootProvider);
  final revision = localDataSource.sessionRevision;
  final manifest = Map<String, dynamic>.from(
    await ref.read(bookManifestProvider(bookId).future),
  );
  if (!ref.context.mounted || revision != localDataSource.sessionRevision) {
    return;
  }
  manifest['hideMinimap'] = hidden;
  await localDataSource.writeBookManifest(bookId, manifest, rootOverride: root);
  if (ref.context.mounted && revision == localDataSource.sessionRevision) {
    ref.invalidate(bookManifestProvider(bookId));
  }
}
