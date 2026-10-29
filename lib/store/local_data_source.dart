// D22.1 修复: 本地数据源 — 替代 HTTP, 直接读文件系统
//
// 设计原则:
// - 数据完全本地化 (D:\Hermes\shufang_storage\)
// - 不依赖 Flask 引擎 / D13 socket 死锁影响
// - 兼容 EditorStore 的 BookInfo / ChapterInfo 模型 (不修改 model 类)
//
// 目录结构:
//   <root>/books/<bookName>/
//     manifest.json               书籍元信息 (可选, 不存在时自动派生)
//     chapters/<chapterName>.md   章节正文 (Markdown 格式)
//     settings/...                设定集 (本文件不涉及)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../services/safe_file_writer.dart';
import '../services/storage_paths.dart';

import 'editor_store.dart' show BookInfo, ChapterInfo, UnitSetting, SettingFile;

/// 本地数据源 (单例)
class LocalDataSource {
  static final LocalDataSource _instance = LocalDataSource._internal();
  factory LocalDataSource() => _instance;
  LocalDataSource._internal();

  /// 当前用户名 (D 阶段: 数据隔离)
  /// null = 默认 (根存储, 兼容旧数据)
  String? _currentUser;
  bool _isAdmin = true;
  String? _workspaceRoot;
  int _sessionRevision = 0;
  int get sessionRevision => _sessionRevision;
  bool _workspaceSelected = false;
  bool get hasWorkspace => _workspaceSelected;
  bool get usesPrimaryStorage => _workspaceSelected && _isAdmin;

  void selectWorkspace(String root, {required bool isPrimary}) {
    _workspaceSelected = true;
    _workspaceRoot = Directory(root).absolute.path;
    _currentUser = null;
    _isAdmin = isPrimary;
    _sessionRevision++;
    _booksCache = null;
    _booksCacheKey = null;
    _chapterCache.clear();
  }

  // E 阶段: 书籍列表缓存 (避免主页每次访问都重新扫描所有章节文件)
  // 在 createBook/createChapter/writeChapter 时自动失效
  List<BookInfo>? _booksCache;
  String? _booksCacheKey; // 用于用户切换时失效

  // 性能优化: 章节正文 LRU 缓存 (避免反复读同一文件)
  // key = "$bookId/$chapterId" → (mtime, content)
  // 容量上限 16, 超出按 FIFO 淘汰
  final Map<String, ({DateTime mtime, String content})> _chapterCache = {};
  static const int _chapterCacheMax = 16;

  /// 设置当前用户 (登录后调用)
  /// admin 用户使用根存储 (兼容现有数据), 其他用户使用 `users/<username>/` 子目录
  void setUser(String username, {bool isAdmin = false}) {
    if (!StoragePaths.validName(username)) throw ArgumentError('无效的工作区名称');
    _workspaceSelected = true;
    _sessionRevision++;
    _workspaceRoot = null;
    _currentUser = username;
    _isAdmin = isAdmin;
    // 用户切换 → 缓存失效
    _booksCache = null;
    _booksCacheKey = null;
    _chapterCache.clear();
  }

  /// 清除用户 (登出时调用)
  void clearUser() {
    _workspaceSelected = false;
    _sessionRevision++;
    _workspaceRoot = null;
    _currentUser = null;
    _isAdmin = true;
    _booksCache = null;
    _booksCacheKey = null;
    _chapterCache.clear();
  }

  /// 使缓存失效 (内部写入操作后调用)
  void _invalidateCache() {
    _booksCache = null;
    _chapterCache.clear();
  }

  /// 数据根目录
  /// - 优先使用环境变量 HERMES_STORAGE_ROOT
  /// - 回退到 D:\Hermes\shufang_storage (Windows 默认)
  String get storageRoot {
    return _resolveRoot();
  }

  String _resolveRoot() {
    if (_workspaceRoot != null) return _workspaceRoot!;
    final baseRoot = StoragePaths.resolveBaseRoot();

    // D 阶段: 数据隔离 — 非管理员用户使用 users/<username>/ 子目录
    if (_currentUser != null && !_isAdmin) {
      return '$baseRoot${Platform.pathSeparator}users${Platform.pathSeparator}$_currentUser';
    }
    return baseRoot;
  }

  /// 书籍根目录: books/  (相对 storageRoot)
  String get booksRoot => '$storageRoot${Platform.pathSeparator}books';

  /// 列出所有书籍 (含其章节列表)
  /// E 阶段: 添加内存缓存, 写入操作自动失效
  Future<List<BookInfo>> listBooks({String? rootOverride}) async {
    // 缓存命中检查
    final cacheKey = rootOverride ?? storageRoot;
    final revision = sessionRevision;
    if (_booksCache != null && _booksCacheKey == cacheKey) {
      return _booksCache!;
    }

    final root = '$cacheKey${Platform.pathSeparator}books';
    final dir = Directory(root);
    if (!await dir.exists()) {
      if (revision == sessionRevision && cacheKey == storageRoot) {
        _booksCache = [];
        _booksCacheKey = cacheKey;
      }
      return [];
    }

    final entries = await dir.list(followLinks: false).toList();
    final bookDirs = entries.whereType<Directory>().toList();

    // E 阶段: 并行扫描各书籍的章节列表
    final books = await Future.wait(
      bookDirs.map((entity) => _loadBookInfo(entity, cacheKey)),
    );

    final result = books.whereType<BookInfo>().toList();
    // 按书籍名排序 (稳定顺序)
    result.sort((a, b) => a.name.compareTo(b.name));

    // 写入缓存
    if (revision == sessionRevision && cacheKey == storageRoot) {
      _booksCache = result;
      _booksCacheKey = cacheKey;
    }
    return result;
  }

  /// 加载单本书信息 (并行辅助)
  Future<BookInfo?> _loadBookInfo(Directory entity, String root) async {
    final bookName = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (bookName.isEmpty || bookName.startsWith('.')) return null;
    try {
      final chapters = await listChapters(bookName, rootOverride: root);
      return BookInfo(id: bookName, name: bookName, chapters: chapters);
    } catch (_) {
      return null;
    }
  }

  /// 列出指定书籍的章节
  Future<List<ChapterInfo>> listChapters(
    String bookId, {
    String? rootOverride,
  }) async {
    final root = rootOverride ?? storageRoot;
    final chaptersDir = Directory(
      '$root${Platform.pathSeparator}books${Platform.pathSeparator}$bookId${Platform.pathSeparator}chapters',
    );
    if (!await chaptersDir.exists()) {
      return [];
    }

    final entries = await chaptersDir.list(followLinks: false).toList();
    final chapterFiles =
        entries.whereType<File>().where((f) {
          final filename = f.uri.pathSegments.last;
          if (!filename.toLowerCase().endsWith('.md')) return false;
          if (filename.startsWith(r'~$')) return false;
          return true;
        }).toList();

    // E 阶段: 并行提取各章节标题
    final chapters = await Future.wait(
      chapterFiles.map((entity) => _loadChapterInfo(entity)),
    );

    // 自然排序 (让 "导入测试章节_1" 在 "导入测试章节_2" 前)
    final result = chapters.whereType<ChapterInfo>().toList();
    result.sort((a, b) => _naturalCompare(a.id, b.id));
    return result;
  }

  /// 加载单章节信息 (并行辅助)
  Future<ChapterInfo?> _loadChapterInfo(File entity) async {
    final filename = entity.uri.pathSegments.last;
    final id = filename.substring(0, filename.length - 3);
    final title = await _extractTitle(entity, fallback: id);
    return ChapterInfo(id: id, title: title);
  }

  /// 读取章节正文 (Markdown 原文)
  /// 性能优化: LRU 缓存 + mtime 失效, 避免反复读同一文件
  Future<String?> readChapter(
    String bookId,
    String chapterId, {
    String? rootOverride,
  }) async {
    if (!StoragePaths.validName(bookId) || !StoragePaths.validName(chapterId)) {
      return null;
    }
    final root = rootOverride ?? storageRoot;
    final cacheKey = '$root/$bookId/$chapterId';
    final path = '$root/books/$bookId/chapters/$chapterId.md';
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    try {
      final stat = await file.stat();
      // 命中缓存: mtime 一致直接返回
      final cached = _chapterCache[cacheKey];
      if (cached != null && cached.mtime == stat.modified) {
        return cached.content;
      }
      final content = await file.readAsString();
      // 写入缓存 (FIFO 淘汰)
      if (_chapterCache.length >= _chapterCacheMax) {
        _chapterCache.remove(_chapterCache.keys.first);
      }
      _chapterCache[cacheKey] = (mtime: stat.modified, content: content);
      return content;
    } catch (_) {
      return null;
    }
  }

  /// 写入章节正文 (用于 Ctrl+S 自动保存)
  Future<bool> writeChapter(
    String bookId,
    String chapterId,
    String content, {
    String? rootOverride,
  }) async {
    if (!StoragePaths.validName(bookId) || !StoragePaths.validName(chapterId)) {
      return false;
    }
    final root = rootOverride ?? storageRoot;
    final path = '$root/books/$bookId/chapters/$chapterId.md';
    final file = File(path);
    try {
      if (!await file.exists()) return false;
      await SafeFileWriter.writeText(path, content, keepPrevious: true);
      // 性能优化: 写入后更新缓存 (避免下次读时再走磁盘)
      final stat = await file.stat();
      final cacheKey = '$root/$bookId/$chapterId';
      if (_chapterCache.length >= _chapterCacheMax &&
          !_chapterCache.containsKey(cacheKey)) {
        _chapterCache.remove(_chapterCache.keys.first);
      }
      _chapterCache[cacheKey] = (mtime: stat.modified, content: content);
      _booksCache = null;
      return true;
    } catch (_) {
      return false;
    }
  }

  void invalidateChapterCache(String bookId, String chapterId) {
    _chapterCache.remove('$storageRoot/$bookId/$chapterId');
  }

  /// 读取书籍 manifest.json
  /// 不存在或解析失败时返回空 Map (调用方可安全写入新字段)
  Future<Map<String, dynamic>> readBookManifest(
    String bookId, {
    String? rootOverride,
  }) async {
    final root = rootOverride ?? storageRoot;
    final path =
        '$root${Platform.pathSeparator}books${Platform.pathSeparator}$bookId${Platform.pathSeparator}manifest.json';
    final file = File(path);
    if (!await file.exists()) return {};
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  /// 写入书籍 manifest.json (覆盖写)
  /// 若书籍目录不存在会先创建, 写入后失效书籍列表缓存
  Future<bool> writeBookManifest(
    String bookId,
    Map<String, dynamic> data, {
    String? rootOverride,
  }) async {
    final root = rootOverride ?? storageRoot;
    final scopedBooks = '$root${Platform.pathSeparator}books';
    final bookDir = Directory('$scopedBooks${Platform.pathSeparator}$bookId');
    final path =
        '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}manifest.json';
    final file = File(path);
    try {
      if (!await bookDir.exists()) {
        await bookDir.create(recursive: true);
      }
      await SafeFileWriter.writeText(file.path, jsonEncode(data));
      _invalidateCache();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 创建新书籍 (在 books/ 下建目录 + manifest.json + chapters/)
  Future<bool> createBook(String bookName) async {
    final scopedBooks = booksRoot;
    if (!StoragePaths.validName(bookName)) return false;
    final bookDir = Directory('$scopedBooks${Platform.pathSeparator}$bookName');
    if (await bookDir.exists()) return false;
    try {
      await bookDir.create(recursive: true);
      final chaptersDir = Directory(
        '$scopedBooks${Platform.pathSeparator}$bookName${Platform.pathSeparator}chapters',
      );
      await chaptersDir.create(recursive: true);
      final settingsDir = Directory(
        '$scopedBooks${Platform.pathSeparator}$bookName${Platform.pathSeparator}settings',
      );
      await settingsDir.create(recursive: true);
      // 写 manifest.json
      final manifest = File(
        '$scopedBooks${Platform.pathSeparator}$bookName${Platform.pathSeparator}manifest.json',
      );
      await manifest.writeAsString(
        jsonEncode({
          'id': bookName,
          'name': bookName,
          'chapter_count': 0,
          'setting_count': 0,
          'version': 1,
          'schema_version': '1.0',
        }),
      );
      // E 阶段: 新增书籍 → 缓存失效
      _invalidateCache();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 创建新章节 (在 chapters/ 下建 .md 文件)
  Future<bool> createChapter(
    String bookId,
    String chapterId, {
    String? title,
  }) async {
    final scopedBooks = booksRoot;
    if (!StoragePaths.validName(bookId) || !StoragePaths.validName(chapterId)) {
      return false;
    }
    final path =
        '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}chapters${Platform.pathSeparator}$chapterId.md';
    final file = File(path);
    if (await file.exists()) return false;
    try {
      final content = '# ${title ?? chapterId}\n';
      await file.writeAsString(content);
      // E 阶段: 新增章节 → 缓存失效 (章节数变化)
      _invalidateCache();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// D37 Phase 2-5 (P1-8): 删除书籍 (整个目录)
  /// 含 manifest.json / chapters/ / settings/ 全部子内容
  /// 返回是否删除成功 (书籍不存在也返回 true)
  Future<bool> deleteBook(String bookId) async {
    final scopedBooks = booksRoot;
    if (!StoragePaths.validName(bookId)) return false;
    final bookDir = Directory('$scopedBooks${Platform.pathSeparator}$bookId');
    try {
      if (await bookDir.exists()) {
        await bookDir.delete(recursive: true);
      }
      _invalidateCache();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// D37 Phase 2-5 (P1-8): 删除章节 (.md + .highlight.json)
  /// 返回是否删除成功 (章节不存在也返回 true)
  Future<bool> deleteChapter(String bookId, String chapterId) async {
    final scopedBooks = booksRoot;
    if (!StoragePaths.validName(bookId) || !StoragePaths.validName(chapterId)) {
      return false;
    }
    final mdPath =
        '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}chapters${Platform.pathSeparator}$chapterId.md';
    final hlPath =
        '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}chapters${Platform.pathSeparator}$chapterId.highlight.json';
    try {
      final mdFile = File(mdPath);
      if (await mdFile.exists()) await mdFile.delete();
      final hlFile = File(hlPath);
      if (await hlFile.exists()) await hlFile.delete();
      _invalidateCache();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 从源文件导入章节 (批量导入用, 零 HTTP 依赖)
  ///
  /// 行为:
  /// - 读取源文件全文 (.txt / .md)
  /// - 推导章节 id (文件名去后缀, 过滤非法字符)
  /// - 若目标章节已存在: 跳过 (返回 false 不视为错误)
  /// - 若目标章节不存在: 写入内容 (若源是 .md 直接复制, 若是 .txt 加 # 标题头)
  /// - 不写空文件: 源文件读取失败时返回 false
  ///
  /// 返回: (success, skipped)
  ///  - success = 新建章节数
  ///  - skipped = 已存在跳过数
  Future<({int success, int skipped})> importChaptersFromFiles(
    String bookId,
    List<({String path, String title})> files,
  ) async {
    final scopedBooks = booksRoot;
    int success = 0;
    int skipped = 0;
    for (final f in files) {
      try {
        final srcFile = File(f.path);
        if (!await srcFile.exists()) continue;
        final content = await srcFile.readAsString();
        if (content.isEmpty) continue;

        // 推导章节 id: 文件名去后缀 + 过滤非法字符
        final filename = f.path.split(Platform.pathSeparator).last;
        final baseName = filename.replaceAll(RegExp(r'\.(txt|md)$'), '');
        final chapterId = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

        final destPath =
            '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}chapters${Platform.pathSeparator}$chapterId.md';
        final destFile = File(destPath);
        if (await destFile.exists()) {
          skipped++;
          continue;
        }

        // .txt 文件加 # 标题头 (转 markdown), .md 文件保留原内容
        final isMarkdown = filename.toLowerCase().endsWith('.md');
        final destContent = isMarkdown ? content : '# ${f.title}\n\n$content';

        await destFile.writeAsString(destContent);
        success++;
      } catch (_) {
        // 单个文件失败不影响其他文件
        continue;
      }
    }
    // 写入操作后失效缓存
    if (success > 0 || skipped > 0) {
      _invalidateCache();
    }
    return (success: success, skipped: skipped);
  }

  /// 检测引擎是否可用 (UI 按钮降级用)
  /// 通过轻量级 socket 探测, 不依赖 HTTP 客户端
  /// 返回 false 时所有 HTTP 按钮应禁用并提示
  static Future<bool> isEngineReachable({
    String host = '127.0.0.1',
    int port = 18766,
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 创建新设定文件 (在 `books/<bookId>/settings/` 下建 .md 文件)
  /// fileName 若无 .md 后缀会自动补上
  /// content 为 null 时写入 `# <fileName>` 头; content 非空时写入指定内容
  Future<bool> createSettingFile(
    String bookId,
    String fileName, [
    String? content,
  ]) async {
    final scopedBooks = booksRoot;
    final name =
        fileName.toLowerCase().endsWith('.md') ? fileName : '$fileName.md';
    final settingsDir = Directory(
      '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}settings',
    );
    try {
      await settingsDir.create(recursive: true);
      final path =
          '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}settings${Platform.pathSeparator}$name';
      final file = File(path);
      if (await file.exists()) return false;
      if (content != null) {
        await file.writeAsString(content);
      } else {
        final title = name.substring(0, name.length - 3);
        await file.writeAsString('# $title\n');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 读取设定文件内容
  /// fileName 若无 .md 后缀会自动补上
  Future<String?> readSetting(String bookId, String fileName) async {
    final scopedBooks = booksRoot;
    final name =
        fileName.toLowerCase().endsWith('.md') ? fileName : '$fileName.md';
    final path =
        '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}settings${Platform.pathSeparator}$name';
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// 写入/覆盖设定文件内容 (D26 #4: 设定编辑器使用与章节保存同机制)
  /// fileName 若无 .md 后缀会自动补上
  /// 返回是否写入成功
  Future<bool> writeSetting(
    String bookId,
    String fileName,
    String content,
  ) async {
    final scopedBooks = booksRoot;
    final name =
        fileName.toLowerCase().endsWith('.md') ? fileName : '$fileName.md';
    final settingsDir = Directory(
      '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}settings',
    );
    try {
      await settingsDir.create(recursive: true);
      final path =
          '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}settings${Platform.pathSeparator}$name';
      final file = File(path);
      await file.writeAsString(content, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// D37 Phase 2-5 (P1-8): 删除设定文件
  /// fileName 若无 .md 后缀会自动补上
  /// 返回是否删除成功 (文件不存在也返回 true)
  Future<bool> deleteSettingFile(String bookId, String fileName) async {
    final scopedBooks = booksRoot;
    final name =
        fileName.toLowerCase().endsWith('.md') ? fileName : '$fileName.md';
    final path =
        '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}settings${Platform.pathSeparator}$name';
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// T-14: 读取章节荧光笔高亮标记 (持久化)
  /// 文件路径: `books/<bookId>/chapters/<chapterId>.highlight.json`
  /// 返回高亮标记列表 (已过滤相同词临时标记), 文件不存在或解析失败返回空列表
  Future<List<Map<String, dynamic>>> readHighlights(
    String bookId,
    String chapterId,
  ) async {
    final scopedBooks = booksRoot;
    final path =
        '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}chapters${Platform.pathSeparator}$chapterId.highlight.json';
    final file = File(path);
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return [];
      final list = decoded['highlights'];
      if (list is! List) return [];
      // 仅返回主高亮 (过滤相同词临时标记, 它们在运行时派生)
      return list
          .whereType<Map<String, dynamic>>()
          .where((m) => (m['id'] as String?)?.startsWith('hl-same-') != true)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// T-14: 写入章节荧光笔高亮标记 (持久化)
  /// 仅持久化主高亮 (用户手动添加的), 相同词临时标记不写入
  /// 返回是否写入成功
  Future<bool> writeHighlights(
    String bookId,
    String chapterId,
    List<Map<String, dynamic>> highlights, {
    String? rootOverride,
  }) async {
    final root = rootOverride ?? storageRoot;
    final path = '$root/books/$bookId/chapters/$chapterId.highlight.json';
    try {
      // 仅持久化主高亮 (过滤相同词临时标记)
      final mainHighlights =
          highlights
              .where(
                (m) => (m['id'] as String?)?.startsWith('hl-same-') != true,
              )
              .toList();
      final data = {'version': 1, 'highlights': mainHighlights};
      await SafeFileWriter.writeText(path, jsonEncode(data));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 列出设定文件 (递归扫描所有书籍的 settings/ 目录)
  /// 返回 UnitSetting 列表 (path = 相对路径, title = 文件名)
  /// E 阶段: 直接扫 books/*/settings/ 目录, 不调 listBooks() (避免触发章节扫描)
  Future<List<UnitSetting>> listSettings() async {
    final scopedBooks = booksRoot;
    final result = <UnitSetting>[];
    try {
      final booksDir = Directory(scopedBooks);
      if (!await booksDir.exists()) return result;

      // 直接列出书籍目录名 (不扫描章节)
      final bookEntries = await booksDir.list(followLinks: false).toList();
      final bookDirs = bookEntries.whereType<Directory>().where((d) {
        final name = d.uri.pathSegments.where((s) => s.isNotEmpty).last;
        return name.isNotEmpty && !name.startsWith('.');
      });

      for (final bookDir in bookDirs) {
        final bookId = bookDir.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final settingsDir = Directory(
          '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}settings',
        );
        if (!await settingsDir.exists()) continue;
        await for (final entity in settingsDir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) continue;
          final filename = entity.uri.pathSegments.last;
          if (!filename.toLowerCase().endsWith('.md')) continue;
          if (filename.startsWith(r'~$')) continue;
          final relPath = '$bookId/settings/$filename';
          result.add(UnitSetting(path: relPath, title: filename));
        }
      }
    } catch (_) {
      // ignore
    }
    return result;
  }

  /// 列出设定文件 (返回 SettingFile 格式, 含文件大小)
  /// E 阶段: 直接扫 books/*/settings/ 目录 + 并行 stat
  Future<List<SettingFile>> listSettingFiles() async {
    final scopedBooks = booksRoot;
    final result = <SettingFile>[];
    try {
      final booksDir = Directory(scopedBooks);
      if (!await booksDir.exists()) return result;

      // 直接列出书籍目录名 (不扫描章节)
      final bookEntries = await booksDir.list(followLinks: false).toList();
      final bookDirs = bookEntries.whereType<Directory>().where((d) {
        final name = d.uri.pathSegments.where((s) => s.isNotEmpty).last;
        return name.isNotEmpty && !name.startsWith('.');
      });

      // 收集所有 settings 文件
      final allFiles = <_SettingFileEntry>[];
      for (final bookDir in bookDirs) {
        final bookId = bookDir.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final settingsDir = Directory(
          '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}settings',
        );
        if (!await settingsDir.exists()) continue;
        await for (final entity in settingsDir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) continue;
          final filename = entity.uri.pathSegments.last;
          if (!filename.toLowerCase().endsWith('.md')) continue;
          if (filename.startsWith(r'~$')) continue;
          final relPath = '$bookId/settings/$filename';
          allFiles.add(
            _SettingFileEntry(path: relPath, name: filename, file: entity),
          );
        }
      }

      // E 阶段: 并行获取所有文件的 stat
      final stats = await Future.wait(allFiles.map((e) => e.file.stat()));
      for (var i = 0; i < allFiles.length; i++) {
        final f = allFiles[i];
        result.add(
          SettingFile(
            path: f.path,
            name: f.name,
            size: stats[i].size,
            lastModified: stats[i].modified,
          ),
        );
      }
    } catch (_) {
      // ignore
    }
    return result;
  }

  /// 列出指定书籍的设定文件 (只扫描单本书的 settings/ 目录)
  Future<List<SettingFile>> listSettingFilesForBook(String bookId) async {
    final scopedBooks = booksRoot;
    final result = <SettingFile>[];
    try {
      final settingsDir = Directory(
        '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}settings',
      );
      if (!await settingsDir.exists()) return result;

      final allFiles = <_SettingFileEntry>[];
      await for (final entity in settingsDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final filename = entity.uri.pathSegments.last;
        if (!filename.toLowerCase().endsWith('.md')) continue;
        if (filename.startsWith(r'~$')) continue;
        final relPath = '$bookId/settings/$filename';
        allFiles.add(
          _SettingFileEntry(path: relPath, name: filename, file: entity),
        );
      }

      final stats = await Future.wait(allFiles.map((e) => e.file.stat()));
      for (var i = 0; i < allFiles.length; i++) {
        final f = allFiles[i];
        result.add(
          SettingFile(
            path: f.path,
            name: f.name,
            size: stats[i].size,
            lastModified: stats[i].modified,
          ),
        );
      }
    } catch (_) {
      // ignore
    }
    return result;
  }

  /// 获取书籍统计 (章节数 + 总字数 + 最后修改时间)
  /// 用于首页书籍卡片摘要
  /// E 阶段: 并行读取所有章节 + 合并 stat 调用, 接受可选 chapters 避免重复扫描
  Future<({int chapterCount, int wordCount, DateTime? lastModified})>
  getBookStats(
    String bookId, {
    List<ChapterInfo>? chapters,
    String? rootOverride,
  }) async {
    final root = rootOverride ?? storageRoot;
    final chList = chapters ?? await listChapters(bookId, rootOverride: root);
    if (chList.isEmpty) {
      return (chapterCount: 0, wordCount: 0, lastModified: null);
    }

    // E 阶段: 并行读取所有章节内容 + stat
    final stats = await Future.wait(
      chList.map((ch) => _readChapterStat(bookId, ch.id, root)),
    );

    int wordCount = 0;
    DateTime? lastModified;
    for (final s in stats) {
      wordCount += s.wordCount;
      if (lastModified == null ||
          (s.modified != null && s.modified!.isAfter(lastModified))) {
        lastModified = s.modified;
      }
    }
    return (
      chapterCount: chList.length,
      wordCount: wordCount,
      lastModified: lastModified,
    );
  }

  /// D37 Phase 3-2: 按日统计近 N 天的写作字数 (用于主页热力图)
  /// 简化方案: 扫所有书的章节, 按 mtime 日期分组累加字数 (length)
  /// days=365 → 返回长度 365 的 List, [0]=今天, [364]=364 天前
  /// 性能: 默认走 _booksCache; 每章一次 stat, 不读内容 (用 stat.size 估算字数)
  Future<List<int>> getDailyWordCounts({
    int days = 365,
    String? rootOverride,
  }) async {
    final root = rootOverride ?? storageRoot;
    final scopedBooks = "$root${Platform.pathSeparator}books";
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final result = List<int>.filled(days, 0);

    final books = await listBooks(rootOverride: root);
    for (final book in books) {
      final chapters = await listChapters(book.id, rootOverride: root);
      for (final ch in chapters) {
        final path =
            '$scopedBooks${Platform.pathSeparator}${book.id}${Platform.pathSeparator}chapters${Platform.pathSeparator}${ch.id}.md';
        final file = File(path);
        try {
          if (!await file.exists()) continue;
          final stat = await file.stat();
          final modified = stat.modified;
          // 同一天 (按本地日期, 不按 24h 倒推)
          final modDate = DateTime(modified.year, modified.month, modified.day);
          final diff = todayDate.difference(modDate).inDays;
          if (diff < 0 || diff >= days) continue;
          // 用 stat.size 估算字数 (UTF-8 中文 1 字 ≈ 3 字节, 不读内容避免 IO)
          // 与 WordCounter.count 不一致但量级正确, 用于热力图着色足够
          result[diff] += (stat.size ~/ 3);
        } catch (_) {
          continue;
        }
      }
    }
    return result;
  }

  /// 读取单章节统计 (并行辅助: 一次读取拿到字数 + 修改时间)
  Future<({int wordCount, DateTime? modified})> _readChapterStat(
    String bookId,
    String chapterId,
    String root,
  ) async {
    final path =
        '$root${Platform.pathSeparator}books${Platform.pathSeparator}$bookId${Platform.pathSeparator}chapters${Platform.pathSeparator}$chapterId.md';
    final file = File(path);
    try {
      if (!await file.exists()) {
        return (wordCount: 0, modified: null);
      }
      // E 阶段: 一次 readAsString + 一次 stat (并行执行)
      final results = await Future.wait([file.readAsString(), file.stat()]);
      final content = results[0] as String;
      final stat = results[1] as FileStat;
      return (wordCount: content.length, modified: stat.modified);
    } catch (_) {
      return (wordCount: 0, modified: null);
    }
  }

  /// 从 Markdown 文件第一行提取 # 标题
  Future<String> _extractTitle(File f, {required String fallback}) async {
    try {
      // 只读前 4KB 足够抓第一行
      final raf = await f.open();
      try {
        final bytes = await raf.read(4096);
        final text = utf8.decode(bytes, allowMalformed: true);
        for (final line in text.split('\n')) {
          final t = line.trim();
          if (t.isEmpty) continue;
          if (t.startsWith('#')) {
            // 去掉前导 # 和空格
            return t.replaceFirst(RegExp(r'^#+\s*'), '').trim();
          }
          // 第一行不是标题, 放弃
          return fallback;
        }
      } finally {
        await raf.close();
      }
    } catch (_) {
      // ignore
    }
    return fallback;
  }

  /// 读取书籍预设片段库 (per-book 持久化)
  /// 文件路径: `books/<bookId>/snippets.json`
  /// 返回片段列表, 文件不存在或解析失败返回空列表
  Future<List<Map<String, dynamic>>> readSnippets(String bookId) async {
    final scopedBooks = booksRoot;
    final path =
        '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}snippets.json';
    final file = File(path);
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return [];
      final list = decoded['snippets'];
      if (list is! List) return [];
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  /// 写入书籍预设片段库 (per-book 持久化)
  Future<bool> writeSnippets(
    String bookId,
    List<Map<String, dynamic>> snippets,
  ) async {
    final scopedBooks = booksRoot;
    final path =
        '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}snippets.json';
    final file = File(path);
    try {
      final data = {'version': 1, 'snippets': snippets};
      await SafeFileWriter.writeText(file.path, jsonEncode(data));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 读取书籍历史剪切板 (per-book 持久化)
  /// 文件路径: `books/<bookId>/clipboard_history.json`
  Future<List<Map<String, dynamic>>> readClipboardHistory(String bookId) async {
    final scopedBooks = booksRoot;
    final path =
        '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}clipboard_history.json';
    final file = File(path);
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return [];
      final list = decoded['history'];
      if (list is! List) return [];
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  /// 写入书籍历史剪切板 (per-book 持久化)
  Future<bool> writeClipboardHistory(
    String bookId,
    List<Map<String, dynamic>> history,
  ) async {
    final scopedBooks = booksRoot;
    final path =
        '$scopedBooks${Platform.pathSeparator}$bookId${Platform.pathSeparator}clipboard_history.json';
    final file = File(path);
    try {
      final data = {'version': 1, 'history': history};
      await SafeFileWriter.writeText(file.path, jsonEncode(data));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 自然排序: 让 _1 < _2 < _10
  static int _naturalCompare(String a, String b) {
    final reg = RegExp(r'(\d+)|(\D+)');
    final aParts = reg.allMatches(a).toList();
    final bParts = reg.allMatches(b).toList();
    final len = aParts.length < bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < len; i++) {
      final ap = aParts[i].group(0)!;
      final bp = bParts[i].group(0)!;
      final an = int.tryParse(ap);
      final bn = int.tryParse(bp);
      if (an != null && bn != null) {
        final cmp = an.compareTo(bn);
        if (cmp != 0) return cmp;
      } else {
        final cmp = ap.compareTo(bp);
        if (cmp != 0) return cmp;
      }
    }
    return a.length.compareTo(b.length);
  }
}

/// 全局单例
final localDataSource = LocalDataSource();

/// E 阶段: 设定文件扫描辅助类 (内部使用)
class _SettingFileEntry {
  final String path;
  final String name;
  final File file;
  const _SettingFileEntry({
    required this.path,
    required this.name,
    required this.file,
  });
}
