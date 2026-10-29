// ============================================================
// D38 架构瘦身: 从 editor_store.dart 抽离的纯数据模型
// ============================================================
// 21 个类型 (enum + class), 0 内部 provider 依赖, 仅 HighlightColor 用 Color.
// editor_store.dart 顶部 `export 'models.dart';` 保持外部 import 0 改动.
// ============================================================

import 'dart:ui' show Color;

/// AI 操作类型
enum AiAction {
  continueWrite, // 续写
  suggest, // 建议
  summary, // 总结
  rewrite, // 改写
  chat, // 聊天 (T-3)
}

/// AI 操作状态
class AiActionState {
  final AiAction action;
  final String status; // 'idle' | 'running' | 'done' | 'error'
  final String content; // 主内容 (content chunks 累积)
  final String reasoning; // V4 推理内容 (T-7)
  final String error;
  final List<Map<String, dynamic>> suggestions; // 建议列表 (仅 suggest)

  const AiActionState({
    required this.action,
    this.status = 'idle',
    this.content = '',
    this.reasoning = '',
    this.error = '',
    this.suggestions = const [],
  });

  AiActionState copyWith({
    String? status,
    String? content,
    String? reasoning,
    String? error,
    List<Map<String, dynamic>>? suggestions,
  }) {
    return AiActionState(
      action: action,
      status: status ?? this.status,
      content: content ?? this.content,
      reasoning: reasoning ?? this.reasoning,
      error: error ?? this.error,
      suggestions: suggestions ?? this.suggestions,
    );
  }
}

/// 单个 Buffer (打开的章节) — 多 Tab 编辑基础
class ChapterBuffer {
  final String bookId;
  final String chapterId;
  final String? title; // 缓存的章节标题 (避免每帧 await)
  final bool isDirty; // 是否有未保存的修改

  const ChapterBuffer({
    required this.bookId,
    required this.chapterId,
    this.title,
    this.isDirty = false,
  });

  /// Buffer 的唯一 key
  String get key => '$bookId:$chapterId';

  ChapterBuffer copyWith({String? title, bool? isDirty}) {
    return ChapterBuffer(
      bookId: bookId,
      chapterId: chapterId,
      title: title ?? this.title,
      isDirty: isDirty ?? this.isDirty,
    );
  }

  @override
  bool operator ==(Object other) => other is ChapterBuffer && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

enum SaveStatus { idle, unsaved, saving, saved, error }

// Phase 2.7: AppRoute 最终 8 值 (management 已删除, 工作区拆为 project/review/engineering)
// D26: engineering 在路由中保留原名, 但显示为"预设" (作家术语, Tab 6)
enum AppRoute {
  home, // 主页/仪表盘
  editor, // 写作 IDE (纯净)
  project, // 设定集 + 单元集 + 大纲 + 矩阵 (工作区)
  review, // 审阅 + 文风 + 主动评审 (工作区)
  engineering, // 资料库 + 就绪度 + 导出 (工作区, 显示为"预设")
  inspire, // 灵感 (SSE 流式)
  settings, // 主题/字体/背景/伴随
  companion, // 伴随预览 (隐藏路由, Ctrl+Shift+P)
}

/// 荧光笔颜色
enum HighlightColor {
  yellow('黄色', Color(0xFFFFEB3B), 0.35),
  red('红色', Color(0xFFFF5252), 0.30),
  blue('蓝色', Color(0xFF42A5F5), 0.30),
  green('绿色', Color(0xFF66BB6A), 0.30),
  purple('紫色', Color(0xFFAB47BC), 0.30);

  final String label;
  final Color color;
  final double alpha;
  const HighlightColor(this.label, this.color, this.alpha);

  Color get renderColor => color.withValues(alpha: alpha);
  Color get minimapColor => color.withValues(alpha: 0.7);
  Color get activeColor => color.withValues(alpha: alpha + 0.2);
}

class HighlightMark {
  final String id;
  final HighlightColor color;
  final int startOffset;
  final int endOffset;
  final String? label;

  const HighlightMark({
    required this.id,
    required this.color,
    required this.startOffset,
    required this.endOffset,
    this.label,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'color': color.name,
    'start': startOffset,
    'end': endOffset,
    'label': label,
  };

  factory HighlightMark.fromJson(Map<String, dynamic> json) {
    return HighlightMark(
      id: json['id'] ?? '',
      color: HighlightColor.values.firstWhere(
        (c) => c.name == json['color'],
        orElse: () => HighlightColor.yellow,
      ),
      startOffset: json['start'] ?? 0,
      endOffset: json['end'] ?? 0,
      label: json['label'],
    );
  }

  HighlightMark copyWith({int? startOffset, int? endOffset}) {
    return HighlightMark(
      id: id,
      color: color,
      startOffset: startOffset ?? this.startOffset,
      endOffset: endOffset ?? this.endOffset,
      label: label,
    );
  }
}

class SameWordMatch {
  final int startOffset;
  final int endOffset;
  final String word;

  const SameWordMatch({
    required this.startOffset,
    required this.endOffset,
    required this.word,
  });
}

class ViewportRange {
  final int firstLine;
  final int lastLine;
  const ViewportRange({required this.firstLine, required this.lastLine});
}

class BookInfo {
  final String id;
  final String name;
  final List<ChapterInfo> chapters;

  const BookInfo({
    required this.id,
    required this.name,
    this.chapters = const [],
  });

  factory BookInfo.fromJson(Map<String, dynamic> json) {
    final chapters =
        (json['chapters'] as List?)
            ?.map((c) => ChapterInfo.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [];
    return BookInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      chapters: chapters,
    );
  }
}

class ChapterInfo {
  final String id;
  final String title;

  const ChapterInfo({required this.id, required this.title});

  factory ChapterInfo.fromJson(Map<String, dynamic> json) {
    return ChapterInfo(id: json['id'] ?? '', title: json['title'] ?? '');
  }
}

class ChatMessage {
  final String role;
  final String content;
  final DateTime timestamp;
  // D37 Phase 2-8 (P1-2): V4 推理内容 (CoT, 与 content 互斥展示)
  // chat 面板之前只渲染 content, reasoning 事件被静默丢弃
  final String reasoning;
  final bool includeInContext;
  final String? directionKey;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.reasoning = '',
    this.includeInContext = true,
    this.directionKey,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? content,
    String? reasoning,
    bool? includeInContext,
  }) {
    return ChatMessage(
      role: role,
      content: content ?? this.content,
      reasoning: reasoning ?? this.reasoning,
      timestamp: timestamp,
      includeInContext: includeInContext ?? this.includeInContext,
      directionKey: directionKey,
    );
  }

  /// Keep the visible transcript intact, but only replay the contiguous tail
  /// prepared under the current author choices. Legacy messages stay visible.
  static List<Map<String, String>> recentContext(
    List<ChatMessage> messages, {
    required String directionKey,
  }) => [
    for (final message
        in messages.reversed
            .takeWhile((message) => message.directionKey == directionKey)
            .toList()
            .reversed)
      if (message.includeInContext)
        {'role': message.role, 'content': message.content},
  ];
}

/// 模型信息
class ModelInfo {
  final String id;
  final String name;
  // D43: 模型所属运营商 (deepseek/openai/qwen/zhipu/custom) + 能力标签
  final String provider;
  final String speed;
  final String description;
  const ModelInfo({
    required this.id,
    required this.name,
    this.provider = '',
    this.speed = '',
    this.description = '',
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? json['id'] ?? '',
      provider: json['provider'] as String? ?? '',
      speed: json['speed'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

// ============================================================
// D43: LLM 运营商 + 运营商详情 (用于专业 API 配置界面)
// ============================================================

/// 运营商单个模型信息
class LlmModelInfo {
  final String id;
  final String name;
  final String speed;
  final String description;
  const LlmModelInfo({
    required this.id,
    required this.name,
    this.speed = '',
    this.description = '',
  });

  factory LlmModelInfo.fromJson(Map<String, dynamic> json) {
    return LlmModelInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? json['id'] ?? '',
      speed: json['speed'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

/// 运营商详情 (后端 /api/llm/providers 返回)
class LlmProviderInfo {
  final String id;
  final String name;
  final bool configured; // 是否已配置 API Key
  final bool isDefault; // 是否当前默认
  final String apiKeyMasked; // 脱敏 Key (sk-abc...xyz)
  final String baseUrl;
  final String baseUrlDefault;
  final String defaultModel;
  final List<LlmModelInfo> models;

  const LlmProviderInfo({
    required this.id,
    required this.name,
    this.configured = false,
    this.isDefault = false,
    this.apiKeyMasked = '',
    this.baseUrl = '',
    this.baseUrlDefault = '',
    this.defaultModel = '',
    this.models = const [],
  });

  factory LlmProviderInfo.fromJson(Map<String, dynamic> json) {
    final modelsList = (json['models'] as List?) ?? [];
    return LlmProviderInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['id'] ?? '',
      configured: json['configured'] as bool? ?? false,
      isDefault: json['is_default'] as bool? ?? false,
      apiKeyMasked: json['api_key_masked'] as String? ?? '',
      baseUrl: json['base_url'] as String? ?? '',
      baseUrlDefault: json['base_url_default'] as String? ?? '',
      defaultModel: json['default_model'] as String? ?? '',
      models:
          modelsList
              .map((m) => LlmModelInfo.fromJson(m as Map<String, dynamic>))
              .toList(),
    );
  }
}

/// /api/llm/providers 顶层响应
class LlmProvidersResponse {
  final String currentProvider;
  final List<String> availableProviders;
  final List<LlmProviderInfo> providers;
  const LlmProvidersResponse({
    required this.currentProvider,
    required this.availableProviders,
    required this.providers,
  });

  factory LlmProvidersResponse.fromJson(Map<String, dynamic> json) {
    final plist = (json['providers'] as List?) ?? [];
    return LlmProvidersResponse(
      currentProvider: json['current_provider'] as String? ?? 'deepseek',
      availableProviders:
          (json['available_providers'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      providers:
          plist
              .map((p) => LlmProviderInfo.fromJson(p as Map<String, dynamic>))
              .toList(),
    );
  }
}

/// /api/llm/test 响应
class LlmTestResult {
  final bool ok;
  final int latencyMs;
  final String error;
  final String responsePreview;
  const LlmTestResult({
    required this.ok,
    this.latencyMs = 0,
    this.error = '',
    this.responsePreview = '',
  });

  factory LlmTestResult.fromJson(Map<String, dynamic> json) {
    return LlmTestResult(
      ok: json['ok'] as bool? ?? false,
      latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
      error: json['error'] as String? ?? '',
      responsePreview: json['response_preview'] as String? ?? '',
    );
  }
}

/// 单元集
class UnitSetInfo {
  final String id;
  final String name;
  final String description;
  final int chapterCount;
  final int settingCount;
  final List<String> chapters;
  final List<String> settings;
  final List<UnitSource> sources;
  final Map<String, dynamic> scope;
  final Map<String, dynamic>? compression;
  final String mode;

  const UnitSetInfo({
    required this.id,
    required this.name,
    this.description = '',
    this.chapterCount = 0,
    this.settingCount = 0,
    this.chapters = const [],
    this.settings = const [],
    this.sources = const [],
    this.scope = const {},
    this.compression,
    this.mode = 'manual',
  });

  factory UnitSetInfo.fromJson(Map<String, dynamic> json) {
    return UnitSetInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      chapterCount: json['chapter_count'] ?? 0,
      settingCount: json['setting_count'] ?? 0,
      chapters: (json['chapters'] as List?)?.cast<String>() ?? [],
      settings: (json['settings'] as List?)?.cast<String>() ?? [],
      sources:
          (json['sources'] as List?)
              ?.map((s) => UnitSource.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      scope: (json['scope'] as Map<String, dynamic>?) ?? {},
      compression: json['compression'] as Map<String, dynamic>?,
      mode: json['mode'] ?? 'manual',
    );
  }
}

class UnitSource {
  final String path;
  final String title;
  final String type;
  const UnitSource({
    required this.path,
    required this.title,
    this.type = 'custom',
  });
  factory UnitSource.fromJson(Map<String, dynamic> json) {
    return UnitSource(
      path: json['path'] ?? '',
      title: json['title'] ?? (json['path']?.toString().split('/').last ?? ''),
      type: json['type'] ?? 'custom',
    );
  }
}

class UnitBook {
  final String id;
  final String name;
  final List<ChapterInfo> chapters;
  const UnitBook({
    required this.id,
    required this.name,
    this.chapters = const [],
  });
  factory UnitBook.fromJson(Map<String, dynamic> json) {
    final list = (json['chapters'] as List?) ?? [];
    return UnitBook(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      chapters:
          list
              .map((c) => ChapterInfo.fromJson(c as Map<String, dynamic>))
              .toList(),
    );
  }
}

class UnitSetting {
  final String path;
  final String title;
  const UnitSetting({required this.path, required this.title});
  factory UnitSetting.fromJson(Map<String, dynamic> json) {
    return UnitSetting(
      path: json['path'] ?? '',
      title: json['title'] ?? (json['path']?.toString().split('/').last ?? ''),
    );
  }
}

class SettingFile {
  final String path;
  final String name;
  final int size;
  final DateTime? lastModified;
  const SettingFile({
    required this.path,
    required this.name,
    this.size = 0,
    this.lastModified,
  });
  factory SettingFile.fromJson(Map<String, dynamic> json) {
    return SettingFile(
      path: json['path'] ?? '',
      name: json['name'] ?? (json['path']?.toString().split('/').last ?? ''),
      size: json['size'] ?? 0,
      lastModified:
          json['last_modified'] != null
              ? DateTime.tryParse(json['last_modified'].toString())
              : null,
    );
  }
}

/// 搜索结果
class SearchResult {
  final String chapterId;
  final String title;
  final List<SearchMatch> matches;
  // D37 Phase 2-3 (P1-7): 搜索结果可能来自不同书, 加 bookId 字段
  // 后端若未返回 book, fromJson 留空, 前端用当前书兜底
  final String bookId;
  const SearchResult({
    required this.chapterId,
    required this.title,
    this.matches = const [],
    this.bookId = '',
  });
  factory SearchResult.fromJson(Map<String, dynamic> json) {
    final list = (json['matches'] as List?) ?? [];
    return SearchResult(
      chapterId: json['chapter_id'] ?? '',
      title: json['title'] ?? '',
      bookId: json['book'] ?? json['book_id'] ?? '',
      matches:
          list
              .map((m) => SearchMatch.fromJson(m as Map<String, dynamic>))
              .toList(),
    );
  }
}

class SearchMatch {
  final int line;
  final String snippet;
  const SearchMatch({required this.line, required this.snippet});
  factory SearchMatch.fromJson(Map<String, dynamic> json) {
    return SearchMatch(line: json['line'] ?? 0, snippet: json['snippet'] ?? '');
  }
}

/// 矩阵查询 key
class MatrixKey {
  final String book;
  final List<String> chapterIds;
  const MatrixKey(this.book, this.chapterIds);

  @override
  bool operator ==(Object other) =>
      other is MatrixKey &&
      other.book == book &&
      _listEq(other.chapterIds, chapterIds);

  @override
  int get hashCode => Object.hash(book, Object.hashAll(chapterIds));

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
