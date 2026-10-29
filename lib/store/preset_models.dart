// =============================================================================
// D46: 前端内置预设运营商 + 模型库
// =============================================================================
// 设计目标:
// - 不依赖引擎即可配置 API Key 和选择模型 (解决"接口不可用"问题)
// - 内置国内主流厂商 + OpenAI, 覆盖 90% 用户场景
// - 支持自定义 (OpenAI 兼容 API: Ollama / vLLM / OpenRouter 等)
//
// 对标业界:
// - Cherry Studio: 内置 10+ 厂商预设, 每个厂商带模型列表
// - LobeChat: 内置厂商列表 + 模型预设, 支持自定义
// - OpenWebUI: 内置 OpenAI/Ollama, 可添加自定义
//
// 注意: 此文件是前端纯静态预设, 与后端 llm_router._PROVIDER_DEFAULTS 镜像.
// 后端启动时以这份预设为默认; 前端引擎未启动时用这份预设展示.
// -----------------------------------------------------------------------------

/// 预设模型信息
class PresetModel {
  final String id;
  final String name;
  final String description;
  final String speed; // 快 / 中 / 慢(深度) / 空

  const PresetModel({
    required this.id,
    required this.name,
    this.description = '',
    this.speed = '',
  });
}

/// 预设运营商信息
class PresetProvider {
  final String id;
  final String name;
  final String baseUrlDefault;
  final String keyEnv; // 对应的环境变量名 (仅参考, 前端不直接用)
  final String keyHint; // Key 输入框提示
  final String officialSite; // 官网 (用户去注册 Key)
  final List<PresetModel> models;

  const PresetProvider({
    required this.id,
    required this.name,
    required this.baseUrlDefault,
    this.keyEnv = '',
    this.keyHint = 'sk-...',
    this.officialSite = '',
    this.models = const [],
  });
}

/// 内置预设运营商列表 (国内主流 + OpenAI + 自定义)
///
/// 顺序即展示顺序: DeepSeek → 通义千问 → 智谱 GLM → 月之暗面 → 豆包 → 文心 → OpenAI → 自定义
const List<PresetProvider> kPresetProviders = [
  // ==================== DeepSeek ====================
  PresetProvider(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrlDefault: 'https://api.deepseek.com/v1',
    keyEnv: 'DEEPSEEK_API_KEY',
    keyHint: 'sk-...',
    officialSite: 'https://platform.deepseek.com',
    models: [
      PresetModel(id: 'deepseek-chat', name: 'DeepSeek Chat', description: '通用对话 (V3)', speed: '快'),
      PresetModel(id: 'deepseek-reasoner', name: 'DeepSeek Reasoner', description: '推理模型 (R1)', speed: '慢(深度)'),
      PresetModel(id: 'deepseek-v4-pro', name: 'DeepSeek V4 Pro', description: '深度写作 (默认)', speed: '慢(深度)'),
      PresetModel(id: 'deepseek-v4-flash', name: 'DeepSeek V4 Flash', description: '快速对话', speed: '快'),
    ],
  ),

  // ==================== 通义千问 (阿里云) ====================
  PresetProvider(
    id: 'qwen',
    name: '通义千问 (阿里云)',
    baseUrlDefault: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    keyEnv: 'DASHSCOPE_API_KEY',
    keyHint: 'sk-...',
    officialSite: 'https://dashscope.console.aliyun.com',
    models: [
      PresetModel(id: 'qwen-max', name: 'Qwen Max', description: '最强模型', speed: '慢(深度)'),
      PresetModel(id: 'qwen-plus', name: 'Qwen Plus', description: '均衡', speed: '中'),
      PresetModel(id: 'qwen-turbo', name: 'Qwen Turbo', description: '快速', speed: '快'),
      PresetModel(id: 'qwen-long', name: 'Qwen Long', description: '长文本 (千万字)', speed: '中'),
    ],
  ),

  // ==================== 智谱 GLM ====================
  PresetProvider(
    id: 'zhipu',
    name: '智谱 GLM',
    baseUrlDefault: 'https://open.bigmodel.cn/api/paas/v4',
    keyEnv: 'ZHIPU_API_KEY',
    keyHint: 'xxx.xxx',
    officialSite: 'https://open.bigmodel.cn',
    models: [
      PresetModel(id: 'glm-4-plus', name: 'GLM-4-Plus', description: '旗舰模型', speed: '慢(深度)'),
      PresetModel(id: 'glm-4-air', name: 'GLM-4-Air', description: '轻量', speed: '快'),
      PresetModel(id: 'glm-4-flash', name: 'GLM-4-Flash', description: '免费', speed: '快'),
      PresetModel(id: 'glm-4-long', name: 'GLM-4-Long', description: '长文本', speed: '中'),
    ],
  ),

  // ==================== 月之暗面 Kimi ====================
  PresetProvider(
    id: 'moonshot',
    name: '月之暗面 Kimi',
    baseUrlDefault: 'https://api.moonshot.cn/v1',
    keyEnv: 'MOONSHOT_API_KEY',
    keyHint: 'sk-...',
    officialSite: 'https://platform.moonshot.cn',
    models: [
      PresetModel(id: 'moonshot-v1-8k', name: 'Kimi 8K', description: '8k 上下文', speed: '快'),
      PresetModel(id: 'moonshot-v1-32k', name: 'Kimi 32K', description: '32k 上下文', speed: '中'),
      PresetModel(id: 'moonshot-v1-128k', name: 'Kimi 128K', description: '128k 上下文', speed: '慢(深度)'),
    ],
  ),

  // ==================== 字节豆包 ====================
  PresetProvider(
    id: 'doubao',
    name: '字节豆包',
    baseUrlDefault: 'https://ark.cn-beijing.volces.com/api/v3',
    keyEnv: 'ARK_API_KEY',
    keyHint: '...',
    officialSite: 'https://www.volcengine.com/product/doubao',
    models: [
      PresetModel(id: 'doubao-pro-4k', name: 'Doubao Pro 4K', description: '专业 4k', speed: '中'),
      PresetModel(id: 'doubao-pro-32k', name: 'Doubao Pro 32K', description: '专业 32k', speed: '慢(深度)'),
      PresetModel(id: 'doubao-pro-128k', name: 'Doubao Pro 128K', description: '专业 128k', speed: '慢(深度)'),
      PresetModel(id: 'doubao-lite-4k', name: 'Doubao Lite 4K', description: '轻量 4k', speed: '快'),
    ],
  ),

  // ==================== 百度文心 ====================
  PresetProvider(
    id: 'wenxin',
    name: '百度文心',
    baseUrlDefault: 'https://qianfan.baidubce.com/v2',
    keyEnv: 'WENXIN_API_KEY',
    keyHint: '...',
    officialSite: 'https://console.bce.baidu.com/qianfan',
    models: [
      PresetModel(id: 'ernie-4.0-turbo-8k', name: 'ERNIE 4.0 Turbo', description: '旗舰', speed: '慢(深度)'),
      PresetModel(id: 'ernie-4.0-8k-latest', name: 'ERNIE 4.0', description: '主力', speed: '中'),
      PresetModel(id: 'ernie-3.5-8k', name: 'ERNIE 3.5', description: '快速', speed: '快'),
      PresetModel(id: 'ernie-long-8k', name: 'ERNIE Long', description: '长文本', speed: '中'),
    ],
  ),

  // ==================== OpenAI ====================
  PresetProvider(
    id: 'openai',
    name: 'OpenAI',
    baseUrlDefault: 'https://api.openai.com/v1',
    keyEnv: 'OPENAI_API_KEY',
    keyHint: 'sk-...',
    officialSite: 'https://platform.openai.com',
    models: [
      PresetModel(id: 'gpt-4o', name: 'GPT-4o', description: '旗舰', speed: '慢(深度)'),
      PresetModel(id: 'gpt-4o-mini', name: 'GPT-4o Mini', description: '轻量', speed: '快'),
      PresetModel(id: 'gpt-4-turbo', name: 'GPT-4 Turbo', description: '上一代旗舰', speed: '慢(深度)'),
      PresetModel(id: 'o1-mini', name: 'O1 Mini', description: '推理', speed: '慢(深度)'),
    ],
  ),

  // ==================== 自定义 (OpenAI 兼容) ====================
  PresetProvider(
    id: 'custom',
    name: '自定义 (OpenAI 兼容)',
    baseUrlDefault: '',
    keyEnv: 'HERMES_LLM_API_KEY',
    keyHint: '任意 Key',
    officialSite: '',
    models: [],
  ),
];

/// 工具函数: 按 provider id 查找预设
PresetProvider? findPresetProvider(String id) {
  for (final p in kPresetProviders) {
    if (p.id == id) return p;
  }
  return null;
}

/// 工具函数: 按模型 id 推断 provider (基于后端 model_prefixes 逻辑的前端镜像)
String inferProviderFromModel(String modelId) {
  if (modelId.startsWith('deepseek-')) return 'deepseek';
  if (modelId.startsWith('gpt-') || modelId.startsWith('o1-')) return 'openai';
  if (modelId.startsWith('qwen-')) return 'qwen';
  if (modelId.startsWith('glm-')) return 'zhipu';
  if (modelId.startsWith('moonshot-')) return 'moonshot';
  if (modelId.startsWith('doubao-')) return 'doubao';
  if (modelId.startsWith('ernie-')) return 'wenxin';
  return 'custom';
}

/// 工具函数: 获取所有预设模型 (扁平列表, 用于设置页全局模型选择)
List<({PresetProvider provider, PresetModel model})> get allPresetModels {
  final list = <({PresetProvider provider, PresetModel model})>[];
  for (final p in kPresetProviders) {
    for (final m in p.models) {
      list.add((provider: p, model: m));
    }
  }
  return list;
}
