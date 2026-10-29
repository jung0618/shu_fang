import 'package:flutter/material.dart'
    show ThemeMode, UndoHistoryController, TextEditingController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_routes.dart';
import 'local_data_source.dart';
import 'workspace_store.dart' show currentWorkspaceProvider;
import 'local_prefs.dart' show PrefsController;
import 'preset_models.dart' show allPresetModels;
import '../widgets/companion_bubble.dart';
import '../services/chapter_save_queue.dart';
import '../services/engine_launcher.dart'
    show EngineStatus, engineStatusProvider, engineBindingProvider;
import 'models.dart'; // D38: Data Models (本文件内部使用 + export 给外部)

// D38 架构瘦身: 纯数据模型抽离到 models.dart, re-export 保持外部 import 0 改动
export 'models.dart';

// ============================================================
// 基础 Provider
// ============================================================

/// 书籍列表 — D22.1 改用本地数据源 (绕过 HTTP/Flask, 不受 D13 socket 死锁影响)
/// 性能优化: autoDispose, 离开页面后释放 (LocalDataSource 有 _booksCache 兜底)
final booksProvider = FutureProvider.autoDispose<List<BookInfo>>((ref) async {
  ref.watch(storageRootProvider);
  return localDataSource.listBooks();
});

/// 当前选中的书籍 ID
final currentBookProvider = StateProvider<String?>((ref) => null);

/// 当前选中的章节 ID
final currentChapterProvider = StateProvider<String?>((ref) => null);

/// Drafts outlive editor widgets; file reads retain error/loading information.
final chapterSaveQueueProvider = ChangeNotifierProvider<ChapterSaveQueue>(
  (ref) => chapterSaveQueue,
);

final storageRootProvider = Provider<String>((ref) {
  ref.watch(currentWorkspaceProvider);
  return localDataSource.storageRoot;
});

final chapterContentProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, chapterKey) async {
      final separator = chapterKey.indexOf(':');
      if (separator < 0) return null;
      final address = ChapterAddress(
        ref.watch(storageRootProvider),
        chapterKey.substring(0, separator),
        chapterKey.substring(separator + 1),
      );
      final draft = chapterSaveQueue.draftFor(address);
      if (draft != null) return draft;
      final content = await localDataSource.readChapter(
        address.book,
        address.chapter,
        rootOverride: address.root,
      );
      if (content == null) {
        throw StateError('章节不存在或无法读取，请检查数据目录；正文未被覆盖。');
      }
      return content;
    });

void invalidateChapterCache(String key) {
  final separator = key.indexOf(':');
  if (separator < 0) return;
  localDataSource.invalidateChapterCache(
    key.substring(0, separator),
    key.substring(separator + 1),
  );
}

/// AI 对话消息列表
final aiMessagesProvider = StateProvider<List<ChatMessage>>((ref) => []);

/// Widget-owned primary editor; consumers capture text/selection synchronously.
final editorControllerProvider = StateProvider<
  ({ChapterAddress address, TextEditingController controller})?
>((ref) => null);

/// AI 流式输出当前 token
final aiStreamingProvider = StateProvider<String?>((ref) => null);

/// D37 Phase 2-7 (P1-1): chat 会话记忆 — session_id 按书持久化
/// 之前每次 _send 都新建 session_id, 后端会话记忆形同虚设, 多轮对话无上下文
/// 现在按 bookId 复用 session_id, 同一本书的对话共享一个 session
/// 简化方案: 内存 Map (重启丢, 接受这种简化; 跨会话持久化可后续接 prefs)
final Map<String, String> _chatSessionByBook = {};

/// 获取/创建某书的 chat session_id (bookId 为 null 时用 'global')
String chatSessionIdFor(String? bookId) {
  final key =
      '${localDataSource.storageRoot}:${localDataSource.sessionRevision}:${bookId ?? 'global'}';
  return _chatSessionByBook.putIfAbsent(
    key,
    () =>
        'flutter-${DateTime.now().microsecondsSinceEpoch}-${_chatSessionByBook.length}',
  );
}

/// 主题模式 — D37 Phase 3-4 (P1-11): 启动读 prefs, watcher 写盘
/// 之前不持久化, 每次重启回默认 light
final themeModeProvider = StateProvider<ThemeMode>((ref) {
  return PrefsController.current.themeMode;
});

// 监听 themeModeProvider 变化, debounce 500ms 写盘 (D37 Phase 3-4)
final themeModeWatcher = Provider<void>((ref) {
  final mode = ref.watch(themeModeProvider);
  Future.microtask(() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await PrefsController.update(
      PrefsController.current.copyWith(themeMode: mode),
    );
  });
});

/// 引擎连接状态
final engineReadyProvider = Provider<bool>((ref) {
  ref.watch(engineBindingProvider);
  return ref.watch(engineStatusProvider) == EngineStatus.ready &&
      apiClient.canUseWorkspace;
});

/// 当前编辑器文本
final editorTextProvider = StateProvider<String>((ref) => '');

/// Only the selected document's latest revision may display "saved".
final saveStatusProvider = Provider<SaveStatus>((ref) {
  final queue = ref.watch(chapterSaveQueueProvider);
  final book = ref.watch(currentBookProvider);
  final chapter = ref.watch(currentChapterProvider);
  if (book == null || chapter == null) return SaveStatus.idle;
  return queue.statusFor(
    ChapterAddress(ref.watch(storageRootProvider), book, chapter),
  );
});

/// Ctrl+S also flushes the split editor, without taking text from global state.
Future<void> saveCurrentChapter(WidgetRef ref) => chapterSaveQueue.flushAll();

/// 章节树折叠状态 (持久化到 user_prefs.json, 跨会话记住)
final sidebarCollapsedProvider = StateProvider<bool>((ref) {
  return PrefsController.current.sidebarCollapsed;
});

// 监听 sidebarCollapsedProvider 变化, debounce 500ms 写盘 (Phase 1.7)
final sidebarCollapseWatcher = Provider<void>((ref) {
  final collapsed = ref.watch(sidebarCollapsedProvider);
  Future.microtask(() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await PrefsController.update(
      PrefsController.current.copyWith(sidebarCollapsed: collapsed),
    );
  });
});

/// 侧边栏展开状态 (与 sidebarCollapsedProvider 互补, 保留向后兼容)
final showSidebarProvider = StateProvider<bool>((ref) {
  return !ref.watch(sidebarCollapsedProvider);
});

/// AI 面板展开状态 — 启动读 prefs, 跨会话记住 (Phase 1.7)
final aiPanelExpandedProvider = StateProvider<bool>((ref) {
  return PrefsController.current.aiPanelExpanded;
});

// 监听 aiPanelExpandedProvider 变化, debounce 500ms 写盘 (Phase 1.7)
// 公开 (无 _ 前缀) 以便 app.dart 顶层 ref.watch 触发
final aiPanelWatcher = Provider<void>((ref) {
  final expanded = ref.watch(aiPanelExpandedProvider);
  Future.microtask(() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await PrefsController.update(
      PrefsController.current.copyWith(aiPanelExpanded: expanded),
    );
  });
});

/// AI 对话面板展开状态 (alias of aiPanelExpandedProvider)
final showAiPanelProvider = StateProvider<bool>((ref) {
  return ref.watch(aiPanelExpandedProvider);
});

/// Minimap 显隐 (会话级, 默认显示; per-book 隐藏由 bookManifestProvider 管理)
final showMinimapProvider = StateProvider<bool>((ref) => true);

/// Compatibility projection; consumers needing errors watch chapterContentProvider.
final currentContentProvider = Provider<String?>((ref) {
  final book = ref.watch(currentBookProvider);
  final chapter = ref.watch(currentChapterProvider);
  if (book == null || chapter == null) return null;
  return ref.watch(chapterContentProvider('$book:$chapter')).valueOrNull;
});

/// 当前章节标题
final currentChapterTitleProvider = Provider<String?>((ref) {
  return ref.watch(currentChapterInfoProvider)?.title;
});

/// 路由 — D22.1 启动默认进入 home (选择书籍), 不是 editor
final appRouteProvider = StateProvider<AppRoute>((ref) => AppRoute.home);

/// 当前选中的 AI 模型 — D40: 启动读 prefs, watcher 写盘 (之前重启回默认)
final selectedModelProvider = StateProvider<String>((ref) {
  return PrefsController.current.selectedModel;
});

// 监听 selectedModelProvider 变化, debounce 500ms 写盘 (D40)
final selectedModelWatcher = Provider<void>((ref) {
  final model = ref.watch(selectedModelProvider);
  Future.microtask(() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await PrefsController.update(
      PrefsController.current.copyWith(selectedModel: model),
    );
  });
});

/// Writing chat/commands budget the complete message contents. Legacy Lore
/// endpoints still use this as a retrieval budget until migrated separately.
enum AiContextStrategy {
  compact('紧凑', '4k 字符', 4000),
  balanced('均衡', '8k 字符', 8000),
  detailed('详尽', '16k 字符', 16000);

  final String label;
  final String desc;
  final int maxChars;
  const AiContextStrategy(this.label, this.desc, this.maxChars);

  static AiContextStrategy fromName(String? name) {
    return AiContextStrategy.values.firstWhere(
      (s) => s.name == name,
      orElse: () => AiContextStrategy.balanced,
    );
  }
}

/// D40: 上下文策略 Provider — 启动读 prefs, watcher 写盘
final aiContextStrategyProvider = StateProvider<AiContextStrategy>((ref) {
  return AiContextStrategy.fromName(PrefsController.current.aiContextStrategy);
});

// 监听 aiContextStrategyProvider 变化, debounce 500ms 写盘 (D40)
final aiContextStrategyWatcher = Provider<void>((ref) {
  final strategy = ref.watch(aiContextStrategyProvider);
  Future.microtask(() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await PrefsController.update(
      PrefsController.current.copyWith(aiContextStrategy: strategy.name),
    );
  });
});

/// 字体族 — D37 Phase 3-4 (P1-11): 启动读 prefs, watcher 写盘 (null = 跟随主题)
final editorFontFamilyProvider = StateProvider<String?>((ref) {
  return PrefsController.current.editorFontFamily;
});

// 监听 editorFontFamilyProvider 变化, debounce 500ms 写盘 (D37 Phase 3-4)
final editorFontFamilyWatcher = Provider<void>((ref) {
  final family = ref.watch(editorFontFamilyProvider);
  Future.microtask(() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await PrefsController.update(
      PrefsController.current.copyWith(editorFontFamily: family),
    );
  });
});

/// 搜索查询
final searchQueryProvider = StateProvider<String>((ref) => '');

/// 搜索结果
final searchResultsProvider = StateProvider<List<SearchResult>>((ref) => []);

/// 搜索进行中
final searchLoadingProvider = StateProvider<bool>((ref) => false);

/// 专注模式
final focusModeProvider = StateProvider<bool>((ref) => false);

/// 编辑器撤销/重做控制器 (D23: 替代假按钮, 真实撤销/重做)
/// D50: 改为 StateProvider, 由当前获焦的 _EditorTextField 注册自己的 controller
/// (之前是全局单例, 章节B按Ctrl+Z会撤销章节A的编辑)
final editorUndoControllerProvider = StateProvider<UndoHistoryController?>(
  (ref) => null,
);

/// 待插入到编辑器的文本（由 AI 面板设置，编辑器监听并插入到光标）
final pendingInsertProvider = StateProvider<String?>((ref) => null);

/// An explicit, chapter-scoped replacement requested by the recovery dialog.
/// The editor consumes it through its own controller and normal save queue.
final pendingChapterRestoreProvider =
    StateProvider<({ChapterAddress address, String text})?>((ref) => null);

// ============================================================
// AI 快速操作状态 (T-8/T-3/T-4: 4 按钮真调用)
// ============================================================

// D38: AiAction / AiActionState 已抽离到 models.dart (通过 export 暴露)

/// 当前 AI 操作状态 (null = 无活动操作)
final aiActionStateProvider = StateProvider<AiActionState?>((ref) => null);

/// 重置 AI 操作状态
void resetAiAction(WidgetRef ref) {
  ref.read(aiActionStateProvider.notifier).state = null;
}

/// 启动 AI 操作 (设置 running 状态)
void startAiAction(WidgetRef ref, AiAction action) {
  ref.read(aiActionStateProvider.notifier).state = AiActionState(
    action: action,
    status: 'running',
  );
}

/// ====================================================================
/// 多 Buffer（多 Tab 编辑）
/// ====================================================================
///
/// 一个 Buffer = 一个打开的章节编辑上下文。
/// 支持同时打开多个章节并快速切换，是分屏 / 多 Tab 协作的基础。
/// D38: ChapterBuffer 已抽离到 models.dart (通过 export 暴露)
/// ====================================================================

/// 所有打开的 Buffer 列表
final openBuffersProvider = StateProvider<List<ChapterBuffer>>((ref) => []);

/// 当前激活的 Buffer 索引 (-1 表示无)
final activeBufferIndexProvider = StateProvider<int>((ref) => -1);

/// 当前激活的 Buffer (派生)
final activeBufferProvider = Provider<ChapterBuffer?>((ref) {
  final i = ref.watch(activeBufferIndexProvider);
  final list = ref.watch(openBuffersProvider);
  if (i < 0 || i >= list.length) return null;
  return list[i];
});

/// Buffer 操作辅助 (使用 WidgetRef, 适用于 ConsumerWidget)
class BufferActions {
  /// 打开或激活一个 Buffer
  static void open(
    WidgetRef ref, {
    required String bookId,
    required String chapterId,
    String? title,
  }) {
    final list = [...ref.read(openBuffersProvider)];
    final key = '$bookId:$chapterId';
    final existingIdx = list.indexWhere((b) => b.key == key);
    if (existingIdx >= 0) {
      // 已存在 -> 激活
      ref.read(activeBufferIndexProvider.notifier).state = existingIdx;
    } else {
      // 新增 -> 追加并激活
      list.add(
        ChapterBuffer(bookId: bookId, chapterId: chapterId, title: title),
      );
      ref.read(openBuffersProvider.notifier).state = list;
      ref.read(activeBufferIndexProvider.notifier).state = list.length - 1;
    }
    // D50: 同步 currentBook/currentChapter 到 active buffer
    // 确保 status_bar / sidebar_tree 高亮与编辑器内容一致
    _syncCurrentToActive(ref);
  }

  /// 关闭一个 Buffer
  static void close(WidgetRef ref, int index) {
    final list = [...ref.read(openBuffersProvider)];
    if (index < 0 || index >= list.length) return;
    // D50-5 (M7): 关闭的 buffer 若是分屏章, 清空 splitChapterProvider
    // (之前依赖 multi_buffer_bar 外部清理, 脆弱; 下沉到内部)
    final closed = list[index];
    if (closed.chapterId == ref.read(splitChapterProvider)) {
      ref.read(splitChapterProvider.notifier).state = null;
    }
    list.removeAt(index);
    ref.read(openBuffersProvider.notifier).state = list;
    final active = ref.read(activeBufferIndexProvider);
    if (list.isEmpty) {
      ref.read(activeBufferIndexProvider.notifier).state = -1;
    } else if (active >= list.length) {
      ref.read(activeBufferIndexProvider.notifier).state = list.length - 1;
    } else if (active > index) {
      ref.read(activeBufferIndexProvider.notifier).state = active - 1;
    }
    // D50: 关闭后同步到新的 active buffer (若仍有)
    _syncCurrentToActive(ref);
  }

  /// 关闭除 active 外的所有
  static void closeOthers(WidgetRef ref) {
    final active = ref.read(activeBufferIndexProvider);
    final list = ref.read(openBuffersProvider);
    if (active < 0 || active >= list.length) return;
    final keep = list[active];
    // D50-5 (M7): 若分屏章不在保留列表, 清空 splitChapterProvider
    if (keep.chapterId != ref.read(splitChapterProvider)) {
      ref.read(splitChapterProvider.notifier).state = null;
    }
    ref.read(openBuffersProvider.notifier).state = [keep];
    ref.read(activeBufferIndexProvider.notifier).state = 0;
    // D50: 同步 currentBook/currentChapter
    _syncCurrentToActive(ref);
  }

  /// 切换到第 N 个 Buffer
  static void activate(WidgetRef ref, int index) {
    final list = ref.read(openBuffersProvider);
    if (index < 0 || index >= list.length) return;
    ref.read(activeBufferIndexProvider.notifier).state = index;
    // D50: 同步 currentBook/currentChapter 到新激活的 buffer
    _syncCurrentToActive(ref);
  }

  /// T-21: 拖拽重排 Buffer
  /// ReorderableListView.onReorder 的 newIndex 在 oldIndex 之前时已 +1, 需修正
  static void reorder(WidgetRef ref, int oldIndex, int newIndex) {
    final list = [...ref.read(openBuffersProvider)];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= list.length) return;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    // 更新 active index
    final active = ref.read(activeBufferIndexProvider);
    int newActive = active;
    if (active == oldIndex) {
      newActive = newIndex;
    } else if (oldIndex < active && newIndex >= active) {
      newActive = active - 1;
    } else if (oldIndex > active && newIndex <= active) {
      newActive = active + 1;
    }
    ref.read(openBuffersProvider.notifier).state = list;
    ref.read(activeBufferIndexProvider.notifier).state = newActive;
    // D50: 重排可能改变 active 指向, 同步 currentBook/currentChapter
    _syncCurrentToActive(ref);
  }

  /// D50: 同步 currentBook/currentChapter 到当前 active buffer
  /// 确保 status_bar (底部状态栏) / sidebar_tree (侧边栏高亮)
  /// 与编辑器主区域 (跟随 activeBuffer) 三者一致
  /// D50-2: 同时重置 saveStatusProvider, 避免新章误显示"已保存"
  static void _syncCurrentToActive(WidgetRef ref) {
    final list = ref.read(openBuffersProvider);
    final active = ref.read(activeBufferIndexProvider);
    if (active < 0 || active >= list.length) {
      // 无 active buffer: 清空 current 状态
      ref.read(currentBookProvider.notifier).state = null;
      ref.read(currentChapterProvider.notifier).state = null;
      return;
    }
    final buf = list[active];
    final oldBook = ref.read(currentBookProvider);
    ref.read(currentBookProvider.notifier).state = buf.bookId;
    ref.read(currentChapterProvider.notifier).state = buf.chapterId;
    // D50-3 (M1): 切书时清空 AI 消息, 避免跨书上下文污染
    // (引擎离线降级走直连 LLM 时会把历史消息发给模型)
    if (oldBook != buf.bookId) {
      ref.read(aiMessagesProvider.notifier).state = [];
      ref.read(aiStreamingProvider.notifier).state = null;
    }
  }

  /// 标记 Buffer 已修改
  static void markDirty(WidgetRef ref, String key, {required bool dirty}) {
    final list = ref.read(openBuffersProvider);
    final idx = list.indexWhere((b) => b.key == key);
    if (idx < 0) return;
    final updated = [
      for (var i = 0; i < list.length; i++)
        if (i == idx) list[i].copyWith(isDirty: dirty) else list[i],
    ];
    ref.read(openBuffersProvider.notifier).state = updated;
  }
}

/// ====================================================================
/// 分屏 (Split View)
/// ====================================================================
///
/// 同窗口左右分屏, 主章在左, 分屏章在右。
/// splitChapterProvider 存分屏章节 id (null = 未分屏)。
/// 分屏章的 book/chapter 从 openBuffers 中按 chapterId 反查, 不走
/// currentContentProvider, 避免与主章全局 provider 冲突。
/// ====================================================================

/// 分屏章节 id (null 表示未分屏)
final splitChapterProvider = StateProvider<String?>((ref) => null);

/// 是否处于分屏模式
final isSplitModeProvider = Provider<bool>(
  (ref) => ref.watch(splitChapterProvider) != null,
);

/// 分屏章对应的 Buffer (从 openBuffers 中按 chapterId 查找)
/// 若分屏章已被关闭, 返回 null
final splitBufferProvider = Provider<ChapterBuffer?>((ref) {
  final splitChapter = ref.watch(splitChapterProvider);
  if (splitChapter == null) return null;
  final buffers = ref.watch(openBuffersProvider);
  return buffers.where((b) => b.chapterId == splitChapter).firstOrNull;
});

/// 分屏章正文内容 (独立读, 不走 currentContentProvider)
final splitContentProvider = FutureProvider<String?>((ref) async {
  final buffer = ref.watch(splitBufferProvider);
  if (buffer == null) return null;
  return ref.watch(chapterContentProvider(buffer.key).future);
});

/// 分屏章标题
final splitChapterTitleProvider = Provider<String?>((ref) {
  final buffer = ref.watch(splitBufferProvider);
  return buffer?.title ?? buffer?.chapterId;
});

/// 分屏章保存 — 将分屏编辑器文本写入指定章节
/// 不更新全局 saveStatusProvider (避免与主章状态冲突)
Future<void> saveSplitChapter(
  WidgetRef ref,
  String book,
  String chapter,
  String text,
) async {
  final address = ChapterAddress(localDataSource.storageRoot, book, chapter);
  chapterSaveQueue.stage(address, text);
  await chapterSaveQueue.flush(address);
}

/// 当前书籍信息
final currentBookInfoProvider = Provider<BookInfo?>((ref) {
  final bookId = ref.watch(currentBookProvider);
  if (bookId == null) return null;
  final booksAsync = ref.watch(booksProvider);
  return booksAsync.whenOrNull(
    data: (books) => books.where((b) => b.id == bookId).firstOrNull,
  );
});

/// 当前章节信息
final currentChapterInfoProvider = Provider<ChapterInfo?>((ref) {
  final chapterId = ref.watch(currentChapterProvider);
  if (chapterId == null) return null;
  final bookInfo = ref.watch(currentBookInfoProvider);
  if (bookInfo == null) return null;
  return bookInfo.chapters.where((c) => c.id == chapterId).firstOrNull;
});

/// 当前章节的单元集上下文
final unitrefContextProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  final book = ref.watch(currentBookProvider);
  final chapter = ref.watch(currentChapterProvider);
  if (book == null || chapter == null) return null;
  try {
    final res = await apiClient.get(
      '${ApiRoutes.unitrefContext}?book=$book&chapter_id=$chapter&include_default=1',
    );
    return res.data?['context'] as Map<String, dynamic>?;
  } catch (_) {
    return null;
  }
});

// ============================================================
// 模型与命令
// ============================================================

/// 可用模型列表 — D22.2 优雅降级 / D46: 引擎不可用时返回前端预设列表
/// 性能优化: autoDispose
final modelsProvider = FutureProvider.autoDispose<List<ModelInfo>>((ref) async {
  try {
    final res = await apiClient.get(ApiRoutes.models);
    final list = (res.data?['models'] as List?) ?? [];
    return list
        .map((m) => ModelInfo.fromJson(m as Map<String, dynamic>))
        .toList();
  } catch (_) {
    // D46: 引擎未启动 → 返回前端预设模型列表 (不返回空, 让用户能选模型)
    return allPresetModels
        .map(
          (pm) => ModelInfo(
            id: pm.model.id,
            name: pm.model.name,
            provider: pm.provider.id,
            speed: pm.model.speed,
            description: pm.model.description,
          ),
        )
        .toList();
  }
});

/// 快捷命令模板 — D22.2 优雅降级
/// 性能优化: autoDispose
/// D37 Phase 1-7 收尾: 后端 /api/commands 返回 {"code":0,"data":[...]} (List data)
/// ApiClient._doRequest 已用 listFromJson 包装到 data['items']
/// 这里通过 res.dataList 直接取, 兼容旧 Map 格式 res.data?['commands']
final commandsProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  try {
    final res = await apiClient.get(ApiRoutes.commands);
    // 优先取 listFromJson 包装的 items (后端返 List data 时)
    final items = res.dataList;
    if (items.isNotEmpty) {
      return items.map((e) => e.toString()).toList();
    }
    // 兼容旧格式: {"data": {"commands": [...]}}
    final cmds = res.data?['commands'] as List? ?? const [];
    return cmds.map((e) => e.toString()).toList();
  } catch (_) {
    return [];
  }
});

// ============================================================
// 单元集 (Unit Set) - 完整 API
// ============================================================

/// 单元集列表 — D22.2 优雅降级
/// 性能优化: autoDispose
final unitSetsProvider = FutureProvider.autoDispose<List<UnitSetInfo>>((
  ref,
) async {
  try {
    final res = await apiClient.get(ApiRoutes.unitSets);
    final list = (res.data?['sets'] as List?) ?? [];
    return list
        .map((s) => UnitSetInfo.fromJson(s as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
});

/// 单元集详情（family by id）— D22.2 优雅降级
/// 性能优化: autoDispose
final unitSetDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, id) async {
      try {
        final res = await apiClient.get(ApiRoutes.unitSet(id));
        return res.data?['set'] as Map<String, dynamic>?;
      } catch (_) {
        return null;
      }
    });

/// 单元集源文件列表（family by id）— D22.2 优雅降级
/// 性能优化: autoDispose
final unitSetSourcesProvider = FutureProvider.autoDispose
    .family<List<UnitSource>, String>((ref, id) async {
      try {
        final res = await apiClient.get(ApiRoutes.unitSetSources(id));
        final list = (res.data?['sources'] as List?) ?? [];
        return list
            .map((s) => UnitSource.fromJson(s as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return [];
      }
    });

/// 书籍→章节列表（用于范围选择器）— D22.2 改用本地数据源
/// 性能优化: autoDispose
final unitBooksProvider = FutureProvider.autoDispose<List<UnitBook>>((
  ref,
) async {
  final books = await localDataSource.listBooks();
  return books
      .map((b) => UnitBook(id: b.id, name: b.name, chapters: b.chapters))
      .toList();
});

/// 可用设定文件（用于源文件选择器）— D22.2 改用本地数据源
/// 性能优化: autoDispose
final unitSettingsProvider = FutureProvider.autoDispose<List<UnitSetting>>((
  ref,
) async {
  return localDataSource.listSettings();
});

/// 单元集变更检测 — D22.2 优雅降级
/// 性能优化: autoDispose
final unitrefChangesProvider = FutureProvider.autoDispose<List<dynamic>>((
  ref,
) async {
  try {
    final res = await apiClient.get(ApiRoutes.unitrefChanges);
    return (res.data?['changes'] as List?) ?? [];
  } catch (_) {
    return [];
  }
});

/// 单元集路径校验 — D22.2 优雅降级
final unitrefValidateProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  try {
    final res = await apiClient.get(ApiRoutes.unitrefValidate);
    return res.data ?? {};
  } catch (_) {
    return {};
  }
});

/// 章节×单元集匹配矩阵 — D22.2 优雅降级
/// 性能优化: autoDispose
final unitrefMatrixProvider = FutureProvider.autoDispose
    .family<Map<String, List<dynamic>>, MatrixKey>((ref, key) async {
      try {
        final res = await apiClient.get(
          ApiRoutes.outlineMatrix(key.book, key.chapterIds.join(',')),
        );
        final raw = res.data?['matrix'] as Map<String, dynamic>?;
        if (raw == null) return {};
        return raw.map((k, v) => MapEntry(k, (v as List)));
      } catch (_) {
        return {};
      }
    });

// ============================================================
// 文档 Provider
// ============================================================

/// 大纲 — D22.2 优雅降级 (引擎不可用时返回 null)
/// 性能优化: autoDispose
final outlineProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  book,
) async {
  try {
    final res = await apiClient.get(ApiRoutes.outline(book));
    return res.data?['outline'] as String?;
  } catch (_) {
    return null;
  }
});

/// 单元集列表 — D22.2 优雅降级
final loreBuildStatusProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  try {
    final res = await apiClient.get(ApiRoutes.loreBuildStatus);
    return (res.data?['status'] as Map<String, dynamic>?) ?? {};
  } catch (_) {
    return {};
  }
});

/// 就绪检查 — D22.2 优雅降级
/// 性能优化: autoDispose
final readinessProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  try {
    final res = await apiClient.get(ApiRoutes.readinessCheck);
    return res.data ?? {};
  } catch (_) {
    return {};
  }
});

/// Training status is available only after a capability handshake.
/// 性能优化: autoDispose
final trainingStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async {
    ref.watch(engineStatusProvider);
    ref.watch(engineBindingProvider);
    if (!apiClient.supports('training_status')) return {};
    try {
      final res = await apiClient.get(ApiRoutes.trainingStatus);
      return res.data ?? {};
    } catch (_) {
      return {};
    }
  },
);

/// 审阅结果
final reviewResultProvider = StateProvider<Map<String, dynamic>?>(
  (ref) => null,
);

/// 主动评审问题
final activeReviewQuestionsProvider = StateProvider<List<Map<String, dynamic>>>(
  (ref) => [],
);

/// 文风分析 — D22.2 优雅降级
final styleProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  try {
    final res = await apiClient.get(ApiRoutes.styleProfile);
    return res.data ?? (res.data?['profile'] as Map<String, dynamic>?);
  } catch (_) {
    return null;
  }
});

/// 设定文件列表 — D22.2 改用本地数据源
final settingsFilesProvider = FutureProvider<List<SettingFile>>((ref) async {
  return localDataSource.listSettingFiles();
});

// ============================================================
// 高亮系统 Provider
// ============================================================

/// 当前章节的荧光笔高亮列表
final highlightsProvider = StateProvider<List<HighlightMark>>((ref) => []);

/// 相同词高亮（临时）
final sameWordHighlightsProvider = StateProvider<List<SameWordMatch>>(
  (ref) => [],
);

/// 当前激活的高亮颜色（同标记联动）
final activeHighlightColorProvider = StateProvider<HighlightColor?>(
  (ref) => null,
);

// Minimap 显隐统一由 showMinimapProvider 管理 (Task 1.2 合并 minimapVisibleProvider)
// per-book 隐藏偏好由 bookManifestProvider 管理, 不在此处

/// 编辑器滚动偏移 0.0-1.0
final scrollOffsetProvider = StateProvider<double>((ref) => 0.0);

/// 编辑器可视区域行范围
final viewportRangeProvider = StateProvider<ViewportRange>(
  (ref) => ViewportRange(firstLine: 0, lastLine: 0),
);

// ============================================================
// D38 架构瘦身: Data Models 已抽离到 models.dart (通过 export 暴露)
// 包含: SaveStatus/AppRoute/HighlightColor/HighlightMark/SameWordMatch/
//       ViewportRange/BookInfo/ChapterInfo/ChatMessage/ModelInfo/
//       UnitSetInfo/UnitSource/UnitBook/UnitSetting/SettingFile/
//       SearchResult/SearchMatch/MatrixKey (共 19 个类型)
// ============================================================

// ============================================================
// D34: 像素助手主动聊天气泡 — 场景触发 watcher
// ============================================================
// 三种场景:
// 1. 写作陪伴: 长时间未操作时主动问候/鼓励
// 2. 状态提醒: 保存成功/失败、字数里程碑
// 3. 上下文感知: 章节切换、打开新书
// ============================================================

/// 场景 2: 保存状态提醒 — 监听 saveStatusProvider 变化
final companionSaveWatcher = Provider<void>((ref) {
  final status = ref.watch(saveStatusProvider);
  if (status == SaveStatus.saved) {
    ref.read(companionBubbleProvider.notifier).remind('已保存');
  } else if (status == SaveStatus.error) {
    ref.read(companionBubbleProvider.notifier).warn('保存失败,请检查');
  }
});

/// 场景 3: 章节切换提醒 — 监听 currentChapterProvider 变化
final companionChapterWatcher = Provider<void>((ref) {
  final chapter = ref.watch(currentChapterProvider);
  if (chapter != null) {
    final info = ref.watch(currentChapterInfoProvider);
    final title = info?.title ?? '新章节';
    ref.read(companionBubbleProvider.notifier).info('正在编辑: $title');
  }
});

/// 场景 1: 写作陪伴 — 监听字数变化, 里程碑鼓励
final companionWordCountWatcher = Provider<void>((ref) {
  // 字数里程碑: 100/500/1000/3000/5000/10000
  final text = ref.watch(editorTextProvider);
  final count = _quickWordCount(text);
  if (count == 100 ||
      count == 500 ||
      count == 1000 ||
      count == 3000 ||
      count == 5000 ||
      count == 10000) {
    ref.read(companionBubbleProvider.notifier).encourage('已写 $count 字,继续加油!');
  }
});

/// 快速字数统计 (不依赖 jieba, 仅统计非空白字符)
int _quickWordCount(String text) {
  if (text.isEmpty) return 0;
  var count = 0;
  for (final ch in text.runes) {
    if (!ch.isWhitespace) count++;
  }
  return count;
}

/// 扩展: 判断字符是否为空白
extension on int {
  bool get isWhitespace {
    return this == 0x20 ||
        this == 0x09 ||
        this == 0x0A ||
        this == 0x0D ||
        this == 0x3000; // 全角空格
  }
}

void clearChatSessions() => _chatSessionByBook.clear();
