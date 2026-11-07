// =============================================================================
// D48: 轻量 LLM 直连客户端 — 不经过 Flask 引擎, 直接调用 OpenAI 兼容 API
// =============================================================================
// 用途: 引擎未启动时, 基础 AI 功能 (summary/改写/续写/建议/聊天) 仍可用.
//
// 配置来源 (按优先级):
//   1. 引擎在线 → 从引擎 /api/llm/providers 获取 baseUrl/defaultModel
//      (但引擎返回的 apiKeyMasked 是脱敏的, 真正的 key 仍需从本地取)
//   2. 引擎离线 → 从本地 PrefsController.current.apiProviders 取
//      - api_key_plain: 明文 key (D48 新增, 仅本地存储)
//      - base_url: 用户配置或预设 baseUrlDefault
//      - default_model: 用户配置或预设首个模型
//
// 安全约束:
//   - 明文 API Key 仅存在本地 user_prefs.json
//   - 仅用于直连 LLM API (Authorization: Bearer header)
//   - 不通过网络传输给除 LLM API 外的任何地方 (不上传引擎/不打印日志)
//
// 防幻觉: 调用方构建 system prompt 时, 用 antiHallucinationBlock 拼接
//        (参考后端 lib_shared/deepseek.py build_system_prompt 的防幻觉段落)
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../api/api_client.dart';
import '../store/local_data_source.dart';
import '../store/local_prefs.dart';
import '../store/preset_models.dart';

/// 防幻觉指令段落 (参考后端 lib_shared/deepseek.py build_system_prompt)
///
/// 调用方在构建 system prompt 时, 把本常量拼到合适位置:
///   ```dart
///   final sys = '你是专业的小说编辑...\n\n${DirectLlmClient.antiHallucinationBlock}';
///   ```
const String _kAntiHallucinationBlock = '''
## 内容真实性要求 (防幻觉)
- 严格基于用户提供的内容回答与创作
- 不要编造未在上下文中出现过的人名、地名、组织名、物品名等专有名词
- 如果用户问及的信息未在上下文中找到, 明确告知"未找到"而不是虚构
- 续写时如需引入新元素, 标注"(新增)"前缀
- 不要复述训练数据中其他作品的情节、人物或专有名词''';

/// 直连 LLM 事件类型 (镜像 ApiClient.SseEventType, 但独立定义避免耦合)
enum DirectLlmEventType {
  content, // 普通内容 chunk
  reasoning, // 推理内容 (DeepSeek reasoner / 部分 OpenAI 兼容模型)
  error, // API/网络错误
  done, // 流结束
}

/// 直连 LLM 事件
class DirectLlmEvent {
  final DirectLlmEventType type;
  final String content;

  const DirectLlmEvent({required this.type, this.content = ''});

  @override
  String toString() => 'DirectLlmEvent(${type.name}: ${content.length} chars)';
}

/// 直连 LLM 配置 (从本地 Prefs 或引擎获取)
class DirectLlmConfig {
  final String apiKey;
  final String baseUrl;
  final String defaultModel;

  const DirectLlmConfig({
    required this.apiKey,
    required this.baseUrl,
    required this.defaultModel,
  });
}

/// 轻量 LLM 直连客户端 (单例式静态方法, 无状态)
class DirectLlmClient {
  DirectLlmClient._();

  static void _requireSession(int revision) {
    if (revision != localDataSource.sessionRevision) {
      throw StateError('工作区已切换，原请求已停止。');
    }
  }

  /// 防幻觉指令段落 (暴露给调用方拼接 system prompt)
  static const String antiHallucinationBlock = _kAntiHallucinationBlock;

  /// 基础防幻觉 system prompt (用于聊天降级等无业务上下文场景)
  /// 含基础人设 + 防幻觉指令, 调用方可直接用作 system message.
  static const String antiHallucinationSystemPrompt =
      '你是一个专业的小说创作助手。请基于用户提供的上下文协助创作, 保持风格一致。\n\n$_kAntiHallucinationBlock';

  /// 读取历史规则导出，保留兼容接口。新写作入口不自动采用未经确认的规则。
  static Future<String> loadConstraintPrompt() async {
    try {
      final root = localDataSource.storageRoot;
      final path =
          '$root${Platform.pathSeparator}.hermes${Platform.pathSeparator}training_rules.json';
      final file = File(path);
      if (!await file.exists()) return '';
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return json['constraint_prompt'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 兼容旧调用；历史训练字符串不升级为系统指令。
  static String buildSystemPromptWithConstraints(String constraintPrompt) {
    final base = '你是一个专业的小说创作助手。请基于用户提供的上下文协助创作, 保持风格一致。';
    // Legacy learned rules have no author acceptance or source version.
    // Keep the argument for old callers, but never promote them to system.
    return '$base\n\n$_kAntiHallucinationBlock';
  }

  /// 兼容旧动作提示接口；仅采用业务提示和固定的证据边界。
  static String buildActionSystemPrompt(
    String basePrompt,
    String constraintPrompt,
  ) {
    return '$basePrompt\n\n$_kAntiHallucinationBlock';
  }

  /// 加载当前运营商的直连配置.
  ///
  /// 优先级:
  ///   1. 引擎在线 → 用引擎返回的 baseUrl/defaultModel + 本地 api_key_plain
  ///   2. 引擎离线 → 用本地 api_key_plain + base_url + default_model
  ///                (base_url 缺失时回退到 preset.baseUrlDefault)
  ///
  /// 返回 null 表示未配置 (无 api_key_plain 或无 baseUrl), 调用方应提示用户去配置.
  static Future<DirectLlmConfig?> loadCurrentConfig() async {
    final prefs = PrefsController.current;
    final providerId = prefs.currentProvider;
    final local =
        (prefs.apiProviders[providerId] as Map<String, dynamic>?) ?? const {};
    final plainKey = local['api_key_plain'] as String? ?? '';
    // 无明文 key → 无法直连 (不尝试用 masked key, 那是脱敏的)
    if (plainKey.isEmpty) return null;

    // 1. 优先尝试从引擎获取 baseUrl/defaultModel (引擎可能配了不同的值)
    String baseUrl = '';
    String model = '';
    try {
      final resp = await apiClient.getLlmProviders();
      final info = resp.providers.where((p) => p.id == providerId).firstOrNull;
      if (info != null) {
        baseUrl = info.baseUrl.isEmpty ? info.baseUrlDefault : info.baseUrl;
        model =
            info.defaultModel.isNotEmpty
                ? info.defaultModel
                : prefs.selectedModel;
      }
    } catch (_) {
      // 引擎离线 → 走本地
    }

    // 2. 引擎未返回 → 用本地 Prefs + 预设
    if (baseUrl.isEmpty) {
      baseUrl = (local['base_url'] as String?) ?? '';
      if (baseUrl.isEmpty) {
        final preset = findPresetProvider(providerId);
        baseUrl = preset?.baseUrlDefault ?? '';
      }
    }
    if (model.isEmpty) {
      model = (local['default_model'] as String?) ?? '';
      if (model.isEmpty) {
        final preset = findPresetProvider(providerId);
        model =
            (preset?.models.isNotEmpty ?? false)
                ? preset!.models.first.id
                : prefs.selectedModel;
      }
    }

    if (baseUrl.isEmpty) return null;
    return DirectLlmConfig(
      apiKey: plainKey,
      baseUrl: baseUrl,
      defaultModel: model,
    );
  }

  /// 流式请求 (OpenAI 兼容 SSE: POST {base_url}/chat/completions with stream=true)
  ///
  /// [messages] 格式: [{role: 'system'|'user'|'assistant', content: '...'}, ...]
  /// [model] 为空时用 config.defaultModel
  static Stream<DirectLlmEvent> streamChat({
    required List<Map<String, String>> messages,
    String? model,
    double temperature = 0.7,
    bool requireComplete = false,
    void Function(Map<String, dynamic>)? onReceipt,
  }) async* {
    final revision = localDataSource.sessionRevision;
    final config = await loadCurrentConfig();
    _requireSession(revision);
    if (config == null) {
      yield const DirectLlmEvent(
        type: DirectLlmEventType.error,
        content: '未配置 API Key, 请在设置 → API 运营商配置中添加',
      );
      return;
    }

    final useModel =
        (model?.isNotEmpty ?? false) ? model! : config.defaultModel;
    final url = _buildChatCompletionsUrl(config.baseUrl);
    final httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 30);

    try {
      final request = await httpClient.postUrl(Uri.parse(url));
      _requireSession(revision);
      request.followRedirects = false;
      request.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      request.headers.set('Authorization', 'Bearer ${config.apiKey}');
      request.headers.set('Accept', 'text/event-stream');
      request.write(
        jsonEncode({
          'model': useModel,
          'messages': messages,
          'stream': true,
          'temperature': temperature,
        }),
      );

      final response = await request.close().timeout(
        const Duration(seconds: 90),
      );
      _requireSession(revision);
      if (response.statusCode != 200) {
        final errBody = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 15));
        _requireSession(revision);
        yield DirectLlmEvent(
          type: DirectLlmEventType.error,
          content:
              'LLM API 错误 (${response.statusCode}): ${_truncateError(errBody)}',
        );
        return;
      }

      // SSE 解析 (参考 api_client.dart ssePostEvents)
      String buffer = '';
      var finishedNormally = false;
      await for (final chunk in response
          .transform(utf8.decoder)
          .timeout(const Duration(seconds: 90))) {
        _requireSession(revision);
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast(); // 保留未完成的行

        for (final line in lines) {
          _requireSession(revision);
          final trimmed = line.trim();
          if (!trimmed.startsWith('data:')) continue;
          final data = trimmed.substring(5).trimLeft();
          if (data.isEmpty) continue;
          if (data == '[DONE]') {
            if (requireComplete && !finishedNormally) {
              yield const DirectLlmEvent(
                type: DirectLlmEventType.error,
                content: '服务未确认正常结束，回复未完成。',
              );
              return;
            }
            yield const DirectLlmEvent(type: DirectLlmEventType.done);
            return;
          }
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final receiptChoices = json['choices'];
            final receiptChoice =
                receiptChoices is List && receiptChoices.isNotEmpty
                    ? receiptChoices.first
                    : null;
            onReceipt?.call({
              if (json['id'] != null) 'id': json['id'],
              if (json['model'] != null) 'model': json['model'],
              if (json['usage'] != null) 'usage': json['usage'],
              if (receiptChoice is Map &&
                  receiptChoice['finish_reason'] != null)
                'finish_reason': receiptChoice['finish_reason'],
            });
            // OpenAI 兼容错误: {"error": {"message": "..."}}
            final err = json['error'];
            if (err != null) {
              final msg =
                  err is Map
                      ? (err['message'] ?? err.toString())
                      : err.toString();
              yield DirectLlmEvent(
                type: DirectLlmEventType.error,
                content: msg.toString(),
              );
              return;
            }
            // OpenAI 兼容: choices[0].delta.content / .reasoning_content
            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;
            final finishReason =
                (choices[0] as Map<String, dynamic>)['finish_reason'];
            if (requireComplete &&
                finishReason != null &&
                finishReason != 'stop') {
              yield const DirectLlmEvent(
                type: DirectLlmEventType.error,
                content: '生成因长度或服务限制而中断，请缩小范围后重试。',
              );
              return;
            }
            if (finishReason == 'stop') finishedNormally = true;
            final delta =
                (choices[0] as Map<String, dynamic>)['delta']
                    as Map<String, dynamic>?;
            if (delta == null) continue;
            final content = delta['content'] as String?;
            if (content != null && content.isNotEmpty) {
              yield DirectLlmEvent(
                type: DirectLlmEventType.content,
                content: content,
              );
            }
            if (revision != localDataSource.sessionRevision) return;
            // DeepSeek reasoner: reasoning_content; 部分兼容: reasoning
            final reasoning =
                delta['reasoning_content'] as String? ??
                delta['reasoning'] as String?;
            if (reasoning != null && reasoning.isNotEmpty) {
              yield DirectLlmEvent(
                type: DirectLlmEventType.reasoning,
                content: reasoning,
              );
            }
          } catch (_) {
            if (requireComplete) {
              yield const DirectLlmEvent(
                type: DirectLlmEventType.error,
                content: '收到无法解析的生成数据，回复未完成。',
              );
              return;
            }
            // Legacy callers tolerate malformed chunks; strict writing
            // requests must not silently omit part of the model response.
          }
        }
      }
      if (requireComplete) {
        yield const DirectLlmEvent(
          type: DirectLlmEventType.error,
          content: '连接在完成标记前结束，回复未完成。',
        );
      } else {
        yield const DirectLlmEvent(type: DirectLlmEventType.done);
      }
    } catch (e) {
      if (revision != localDataSource.sessionRevision) return;
      yield DirectLlmEvent(
        type: DirectLlmEventType.error,
        content: '直连 LLM 失败: $e',
      );
    } finally {
      httpClient.close(force: true);
    }
  }

  /// 非流式请求 (OpenAI 兼容: POST {base_url}/chat/completions with stream=false)
  ///
  /// 返回 assistant 消息内容. 失败抛 Exception (含状态码 + 截断的错误 body).
  static Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
    String? model,
    double temperature = 0.7,
  }) async {
    final revision = localDataSource.sessionRevision;
    final config = await loadCurrentConfig();
    _requireSession(revision);
    if (config == null) {
      throw Exception('未配置 API Key, 请在设置 → API 运营商配置中添加');
    }

    final useModel =
        (model?.isNotEmpty ?? false) ? model! : config.defaultModel;
    final url = _buildChatCompletionsUrl(config.baseUrl);
    final httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 60);

    try {
      final request = await httpClient.postUrl(Uri.parse(url));
      _requireSession(revision);
      request.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      request.headers.set('Authorization', 'Bearer ${config.apiKey}');
      request.write(
        jsonEncode({
          'model': useModel,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          'stream': false,
          'temperature': temperature,
        }),
      );

      final response = await request.close();
      _requireSession(revision);
      final body = await response.transform(utf8.decoder).join();
      _requireSession(revision);
      if (response.statusCode != 200) {
        throw Exception(
          'LLM API 错误 (${response.statusCode}): ${_truncateError(body)}',
        );
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('LLM API 返回空 choices');
      }
      final message =
          (choices[0] as Map<String, dynamic>)['message']
              as Map<String, dynamic>?;
      return message?['content'] as String? ?? '';
    } finally {
      httpClient.close(force: true);
    }
  }

  /// 拼接 chat/completions URL (处理 base_url 末尾斜杠)
  static String _buildChatCompletionsUrl(String baseUrl) {
    final trimmed =
        baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl;
    return '$trimmed/chat/completions';
  }

  /// 截断错误信息 (避免超长 JSON 错误 body 淹没 UI)
  static String _truncateError(String s) {
    if (s.length <= 300) return s;
    return '${s.substring(0, 300)}...';
  }
}
