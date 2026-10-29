// ============================================================
// D38 ApiRoutes: 后端 API 路径与端口的集中常量层
// ============================================================
// 之前: 47 处 apiClient.post('/api/xxx/yyy') 散落 16 个文件
//   - 路径字符串易写错 (P0 修复时多次因路径写错导致断链)
//   - 后端改路径需要全文 grep
// 现在: 所有路径在此声明, 调用方用 ApiRoutes.xxx 引用
//   - IDE 自动补全, 拼写错误编译期暴露
//   - 后端路径变更只改本文件
// ============================================================

/// 后端 Flask 引擎端口 (与 hermes_public/engine/app.py 一致)
const int kEnginePort = 18766;

/// Legacy default only. Active clients use EngineEndpoint + SHUFANG_ENGINE_URL.
const String kEngineBaseUrl = 'http://localhost:$kEnginePort';

/// 集中管理所有后端 API 路径
class ApiRoutes {
  // ============================================================
  // 基础
  // ============================================================
  static const String authToken = '/api/auth/token';
  static const String ping = '/api/ping';
  static const String engineCapabilities = '/api/engine/capabilities';
  static const String models = '/api/models';
  static const String commands = '/api/commands';

  // ============================================================
  // AI 对话 / 灵感 / 总结 / 改写 / 建议
  // ============================================================
  static const String chatSend = '/api/chat/send';
  static const String chatContextSend = '/api/chat/send-context';
  static const String inspireGenerate = '/api/inspire/generate';
  static const String inspireHistory = '/api/inspire/history';
  static const String suggestionGenerate = '/api/suggestion/generate';
  static const String summary = '/api/summary';
  static const String rewrite = '/api/rewrite';

  // ============================================================
  // D43: LLM 运营商管理 (provider 配置/测试/切换)
  // ============================================================
  static const String llmProviders = '/api/llm/providers';
  static const String llmConfig = '/api/llm/config';
  static const String llmTest = '/api/llm/test';
  static const String llmSwitch = '/api/llm/switch';
  static String llmConfigOf(String provider) => '/api/llm/config/$provider';

  // ============================================================
  // 审阅
  // ============================================================
  static const String reviewParagraph = '/api/review/paragraph';
  static const String reviewCrossChapter = '/api/review/cross-chapter';
  static const String activeReviewPreferences =
      '/api/active-review/preferences';
  static const String activeReviewGenerate = '/api/active-review/generate';
  static const String activeReviewFeedback = '/api/active-review/feedback';

  // ============================================================
  // 搜索
  // ============================================================
  static const String search = '/api/search';

  // ============================================================
  // 大纲
  // ============================================================
  /// 大纲读取 (GET) — 参数: bookId
  /// 大纲保存 (PUT) — 参数: bookId, body: outline
  static String outline(String bookId) => '/api/outline/$bookId';

  /// 大纲矩阵 (GET) — 参数: bookId, chapterIds (逗号分隔)
  static String outlineMatrix(String bookId, String chapterIdsCsv) =>
      '/api/outline/matrix?book=$bookId&chapter_ids=$chapterIdsCsv';

  /// 大纲生成 (POST) — 参数: bookId, chapterIds
  static const String outlineGenerate = '/api/outline/generate';

  // ============================================================
  // 索引 / Lore build
  // ============================================================
  static const String loreBuild = '/api/lore/build';
  static const String loreBuildStatus = '/api/lore/build/status';
  static const String indexIncremental = '/api/index/incremental';
  static const String unitrefChanges = '/api/unitref/changes';
  static const String unitrefValidate = '/api/unitref/validate';
  static const String unitrefContext = '/api/unitref/context';

  // ============================================================
  // Unit Sets (单元集)
  // ============================================================
  static const String unitSets = '/api/unit/sets';
  static String unitSet(String setId) => '/api/unit/sets/$setId';
  static String unitSetSources(String setId) => '/api/unit/sets/$setId/sources';
  static String unitSetScope(String setId) => '/api/unit/sets/$setId/scope';
  static String unitSetCompress(String setId) =>
      '/api/unit/sets/$setId/compress';
  static String unitSetSummary(String setId) => '/api/unit/sets/$setId/summary';

  // ============================================================
  // 风格 / 就绪度 / 训练
  // ============================================================
  static const String styleProfile = '/api/style/profile';

  /// 定稿检查 (POST) — 参数: bookId, chapterId
  static String styleCheck(String bookId, String chapterId) =>
      '/api/style/$bookId/$chapterId/check';

  /// 定稿 (POST) — 参数: bookId, chapterId
  static String styleFinalize(String bookId, String chapterId) =>
      '/api/style/$bookId/$chapterId/finalize';
  static const String readinessCheck = '/api/readiness/check';
  static const String trainingStatus = '/api/training/status';
  static const String evolutionRules = '/api/evolution/rules';
  static const String evolutionExport = '/api/evolution/export';

  // ============================================================
  // 导出 / 文件
  // ============================================================
  static const String exportDocx = '/api/export/docx';
  static const String exportTxt = '/api/export/txt';
  static const String exportMd = '/api/export/md';
}
