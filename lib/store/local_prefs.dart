// 全局偏好持久化 — user_prefs.json 读写, 跨会话记住 UI 状态
//
// 设计原则:
// - 与 editor_store.dart 中的 provider 配合: provider 是内存态, PrefsController 是持久化层
// - 启动时 init() 读盘 → 同步到 provider; provider 变更 → 写盘
// - 损坏文件回退默认值, 不阻塞 UI
// - 写失败静默, 不弹错误 (心流保护)

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show ThemeMode;

import 'local_data_source.dart' show localDataSource;
import '../services/safe_file_writer.dart';

/// 用户全局偏好 (跨会话持久化的 UI 状态子集)
@immutable
class UserPrefs {
  final bool aiPanelExpanded;
  final bool sidebarCollapsed;
  final ThemeMode themeMode;
  final String? editorFontFamily;
  // D37 Phase 3-5: 最近打开的书籍 ID (主页排序 + 启动恢复)
  final String? lastOpenedBookId;
  final String? lastWorkspaceId;
  final Map<String, String> lastOpenedBooks;
  // D40: AI 模型选择持久化 (D45: 默认改为 deepseek-v4-pro 深度写作)
  final String selectedModel;
  // D40: AI 上下文策略 (compact 4k / balanced 8k / detailed 16k)
  final String aiContextStrategy;
  // D43: LLM 运营商持久化层 — 上次切换的默认运营商 + 各运营商本地缓存
  // (后端运行时配置仅存内存, 重启后回退到 .env; 这里缓存仅用于 UI 状态恢复,
  //  实际 Key 仍需用户重新输入或后端 .env 已配置)
  // D48: apiProviders 新增 api_key_plain 字段 (明文 Key, 仅本地直连 LLM 用, 不上传引擎/不显示)
  final String currentProvider;
  // {deepseek: {api_key_masked, api_key_plain, base_url, default_model}, ...}
  // - api_key_masked: 脱敏 Key, 用于 UI 显示 (sk-abc...xyz)
  // - api_key_plain:  明文 Key, 仅用于直连 LLM (D48 新增, 不通过网络传给除 LLM API 外的任何地方)
  final Map<String, dynamic> apiProviders;

  const UserPrefs({
    this.aiPanelExpanded = false,
    this.sidebarCollapsed = false,
    this.themeMode = ThemeMode.light,
    this.editorFontFamily,
    this.lastOpenedBookId,
    this.lastWorkspaceId,
    this.lastOpenedBooks = const {},
    this.selectedModel = 'deepseek-v4-pro',
    this.aiContextStrategy = 'balanced',
    this.currentProvider = 'deepseek',
    this.apiProviders = const {},
  });

  Map<String, dynamic> toJson() => {
    'aiPanelExpanded': aiPanelExpanded,
    'sidebarCollapsed': sidebarCollapsed,
    'themeMode': themeMode.name,
    'editorFontFamily': editorFontFamily,
    if (lastOpenedBookId != null) 'lastOpenedBookId': lastOpenedBookId,
    if (lastWorkspaceId != null) 'lastWorkspaceId': lastWorkspaceId,
    'lastOpenedBooks': lastOpenedBooks,
    'selectedModel': selectedModel,
    'aiContextStrategy': aiContextStrategy,
    'currentProvider': currentProvider,
    'apiProviders': apiProviders,
  };

  factory UserPrefs.fromJson(Map<String, dynamic> j) => UserPrefs(
    // D26 #5: 已存在配置文件时, 仍尊重用户上次选择 (不覆盖)
    aiPanelExpanded: j['aiPanelExpanded'] as bool? ?? true,
    sidebarCollapsed: j['sidebarCollapsed'] as bool? ?? false,
    themeMode: ThemeMode.values.firstWhere(
      (m) => m.name == j['themeMode'],
      orElse: () => ThemeMode.light,
    ),
    editorFontFamily: j['editorFontFamily'] as String?,
    lastOpenedBookId: j['lastOpenedBookId'] as String?,
    lastWorkspaceId: j['lastWorkspaceId'] as String?,
    lastOpenedBooks: _readLastOpenedBooks(j['lastOpenedBooks']),
    selectedModel: j['selectedModel'] as String? ?? 'deepseek-v4-pro',
    aiContextStrategy: j['aiContextStrategy'] as String? ?? 'balanced',
    currentProvider: j['currentProvider'] as String? ?? 'deepseek',
    apiProviders: (j['apiProviders'] as Map<String, dynamic>?) ?? const {},
  );

  UserPrefs copyWith({
    bool? aiPanelExpanded,
    bool? sidebarCollapsed,
    ThemeMode? themeMode,
    String? editorFontFamily,
    String? lastOpenedBookId,
    String? lastWorkspaceId,
    Map<String, String>? lastOpenedBooks,
    String? selectedModel,
    String? aiContextStrategy,
    String? currentProvider,
    Map<String, dynamic>? apiProviders,
  }) => UserPrefs(
    aiPanelExpanded: aiPanelExpanded ?? this.aiPanelExpanded,
    sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
    themeMode: themeMode ?? this.themeMode,
    editorFontFamily: editorFontFamily ?? this.editorFontFamily,
    lastOpenedBookId: lastOpenedBookId ?? this.lastOpenedBookId,
    lastWorkspaceId: lastWorkspaceId ?? this.lastWorkspaceId,
    lastOpenedBooks: lastOpenedBooks ?? this.lastOpenedBooks,
    selectedModel: selectedModel ?? this.selectedModel,
    aiContextStrategy: aiContextStrategy ?? this.aiContextStrategy,
    currentProvider: currentProvider ?? this.currentProvider,
    apiProviders: apiProviders ?? this.apiProviders,
  );

  static const UserPrefs defaults = UserPrefs();

  static Map<String, String> _readLastOpenedBooks(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }
}

/// 全局 prefs 单例 (内存态 + 异步写盘)
///
/// 使用流程:
/// 1. main() 启动时 await PrefsController.init()
/// 2. 任意 provider 监听变化时调 PrefsController.update(next)
/// 3. 读取当前值: PrefsController.current.aiPanelExpanded 等
class PrefsController {
  static UserPrefs _current = UserPrefs.defaults;
  static File? _file;
  static bool _initialized = false;

  static UserPrefs get current => _current;
  static bool get initialized => _initialized;

  /// 启动时调用一次, 读盘加载
  static Future<void> init() async {
    if (_initialized) return;
    final root = localDataSource.storageRoot; // String, 非 Directory
    _file = File('$root${Platform.pathSeparator}user_prefs.json');
    try {
      if (await _file!.exists()) {
        final raw = await _file!.readAsString();
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _current = UserPrefs.fromJson(j);
      }
    } catch (_) {
      // 损坏回退默认值
      _current = UserPrefs.defaults;
    }
    _initialized = true;
  }

  /// 更新并异步写盘 (写失败静默, 不阻塞 UI)
  static Future<void> update(UserPrefs next) async {
    _current = next;
    try {
      final file = _file;
      if (file != null) {
        await SafeFileWriter.writeText(file.path, jsonEncode(next.toJson()));
      }
    } catch (_) {
      // 静默失败, 不阻塞 UI (心流保护)
    }
  }
}
