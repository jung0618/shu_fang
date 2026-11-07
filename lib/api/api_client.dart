import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../store/models.dart';
import '../store/local_data_source.dart';
import '../services/engine_config.dart';
import 'api_routes.dart';
import 'engine_capabilities.dart';

/// API 统一响应格式
class ApiResponse {
  final int code;
  final Map<String, dynamic>? data;
  final String message;

  const ApiResponse({required this.code, this.data, this.message = 'ok'});

  bool get ok => code == 0;

  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    return ApiResponse(
      code: json['code'] ?? -1,
      data: json['data'] is Map<String, dynamic> ? json['data'] : null,
      message: json['message'] ?? '',
    );
  }

  /// D37 Phase 1-7: 后端 /api/commands 返回 List (非 Map)
  /// 包装 List 到 data 里, 让前端通过 dataList 取
  factory ApiResponse.listFromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    if (rawData is List) {
      return ApiResponse(
        code: json['code'] ?? -1,
        data: {'items': rawData},
        message: json['message'] ?? '',
      );
    }
    return ApiResponse.fromJson(json);
  }

  /// 取 List 数据 (后端返回 List 时用)
  List<dynamic> get dataList => data?['items'] as List? ?? [];
}

/// ShuFang HTTP + SSE 客户端 (单例)
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal() : _endpoint = null;

  /// Separate local transport for contract tests and embedded hosts.
  ApiClient.at(Uri endpoint)
    : _endpoint = EngineEndpoint.resolve({'SHUFANG_ENGINE_URL': '$endpoint'});

  final Uri? _endpoint;
  Uri get endpoint => _endpoint ?? EngineEndpoint.resolve();
  String get endpointDescription {
    try {
      return '$endpoint';
    } on FormatException {
      return '引擎地址配置无效';
    }
  }

  String get _baseUrl => '$endpoint';
  String? _token;
  final HttpClient _httpClient = HttpClient();
  EngineCapabilities? _capabilities;
  final _bindingChanges = StreamController<EngineCapabilities?>.broadcast();
  Stream<EngineCapabilities?> get bindingChanges => _bindingChanges.stream;
  EngineCapabilities? get capabilities =>
      canUseWorkspace ? _capabilities : null;
  int? _boundRevision;
  String? _boundRoot;
  int _connectionGeneration = 0;

  bool get canUseWorkspace =>
      localDataSource.hasWorkspace &&
      _boundRevision == localDataSource.sessionRevision &&
      _boundRoot == localDataSource.storageRoot &&
      _token != null &&
      _capabilities?.supports('workspace_api') == true;

  bool supports(String name) =>
      canUseWorkspace && _capabilities!.supports(name);

  void disconnect() {
    _connectionGeneration++;
    _token = null;
    _capabilities = null;
    _boundRevision = null;
    _boundRoot = null;
    if (!_bindingChanges.isClosed) _bindingChanges.add(null);
  }

  void close() {
    disconnect();
    _httpClient.close(force: true);
    unawaited(_bindingChanges.close());
  }

  // Every legacy file route is constrained by an authenticated workspace binding.
  void _requireWorkspace([int? revision]) {
    if (!canUseWorkspace) {
      throw StateError('引擎尚未连接当前工作区；请在「工作区与工具」中连接。');
    }
    if (revision != null && revision != localDataSource.sessionRevision) {
      throw StateError('工作区已切换，原请求已停止。');
    }
  }

  void _checkBindingResponse(HttpClientResponse response) {
    if (response.statusCode == 409 &&
        response.headers.value('X-ShuFang-Binding-Invalid') == '1') {
      disconnect();
      unawaited(
        response
            .drain<void>()
            .timeout(const Duration(seconds: 2))
            .catchError((Object _) {}),
      );
      throw StateError('引擎或工作区已改变，请重新连接。');
    }
  }

  /// Authenticate and bind atomically. A late or timed-out handshake cannot bind.
  Future<void> init() async {
    disconnect();
    if (!localDataSource.hasWorkspace) {
      throw StateError('请先选择工作区。');
    }
    final revision = localDataSource.sessionRevision;
    final root = localDataSource.storageRoot;
    final generation = _connectionGeneration;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final result = await (() async {
        Future<Map<String, dynamic>> read(String path, [String? token]) async {
          final request = await client.getUrl(endpoint.resolve(path));
          request.followRedirects = false;
          if (token != null) request.headers.set('X-ShuFang-Token', token);
          final response = await request.close();
          // Identity replies are small. Refuse unbounded or foreign services.
          var size = 0;
          final bytes = <int>[];
          await for (final chunk in response) {
            size += chunk.length;
            if (size > 65536) throw const FormatException('引擎身份响应过大。');
            bytes.addAll(chunk);
          }
          if (response.statusCode != 200) {
            throw HttpException('引擎身份核对失败（HTTP ${response.statusCode}）。');
          }
          final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          if (json['code'] != 0 || json['data'] is! Map<String, dynamic>) {
            throw const FormatException('引擎身份响应不兼容。');
          }
          return json['data'] as Map<String, dynamic>;
        }

        final auth = await read(ApiRoutes.authToken);
        final token = auth['token'];
        if (token is! String || token.isEmpty) {
          throw const FormatException('引擎认证信息为空。');
        }
        final capabilities = EngineCapabilities.fromJson(
          await read(ApiRoutes.engineCapabilities, token),
        );
        if (!capabilities.supports('workspace_api') ||
            await EngineCapabilities.canonicalRoot(root) !=
                await EngineCapabilities.canonicalRoot(
                  capabilities.workspaceRoot,
                )) {
          throw StateError('此引擎连接的是其他目录或目录不可用，请连接当前工作区的引擎。');
        }
        return (token: token, capabilities: capabilities);
      })().timeout(const Duration(seconds: 5));
      if (generation != _connectionGeneration ||
          revision != localDataSource.sessionRevision ||
          !localDataSource.hasWorkspace ||
          root != localDataSource.storageRoot) {
        throw StateError('工作区或连接已切换，原连接结果已丢弃。');
      }
      _token = result.token;
      _capabilities = result.capabilities;
      _boundRevision = revision;
      _boundRoot = root;
      _bindingChanges.add(result.capabilities);
    } finally {
      client.close(force: true);
    }
  }

  /// Health only; does not set connection readiness or authorize workspace access.
  Future<bool> ping() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      return await (() async {
        final request = await client.getUrl(endpoint.resolve(ApiRoutes.ping));
        request.followRedirects = false;
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode == 200;
      })().timeout(const Duration(seconds: 2));
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// GET 请求
  Future<ApiResponse> get(String path) async {
    return _request('GET', path);
  }

  /// POST 请求
  Future<ApiResponse> post(String path, {Map<String, dynamic>? body}) async {
    return _request('POST', path, body: body);
  }

  /// PUT 请求
  Future<ApiResponse> put(String path, {Map<String, dynamic>? body}) async {
    return _request('PUT', path, body: body);
  }

  /// PUT 裸文本请求 (D37 Phase 0-2: 大纲后端读 get_data(as_text=True), 不能发 JSON)
  Future<ApiResponse> putText(String path, String text) async {
    _requireWorkspace();
    final revision = localDataSource.sessionRevision;
    final uri = Uri.parse('$_baseUrl$path');
    final request = await _httpClient.putUrl(uri);
    _requireWorkspace(revision);
    _attachHeaders(request);
    request.headers.set('Content-Type', 'text/plain; charset=utf-8');
    request.write(text);
    final response = await request.close();
    _requireWorkspace(revision);
    _checkBindingResponse(response);
    final responseBody = await response.transform(utf8.decoder).join();
    _requireWorkspace(revision);
    try {
      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      return ApiResponse.fromJson(json);
    } catch (_) {
      // 非 JSON 响应 (例如 405/500 plain text), 用 statusCode 推断
      return ApiResponse(
        code: response.statusCode == 200 ? 0 : -1,
        message: 'HTTP ${response.statusCode}: $responseBody',
      );
    }
  }

  /// 下载二进制文件 (D37 Phase 0-1: 导出 docx 后端返二进制流, 不能走 jsonDecode)
  /// 返回 (bytes, suggestedFilename), 失败抛 Exception (含后端错误信息)
  Future<({List<int> bytes, String filename})> downloadFile(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    _requireWorkspace();
    final revision = localDataSource.sessionRevision;
    final uri = Uri.parse('$_baseUrl$path');
    final request = await _httpClient.postUrl(uri);
    _requireWorkspace(revision);
    _attachHeaders(request);
    request.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    _requireWorkspace(revision);
    _checkBindingResponse(response);
    // 错误响应通常是 JSON (success False)
    final contentType = response.headers.value('content-type') ?? '';
    if (!contentType.contains('application/vnd.openxmlformats') &&
        !contentType.contains('text/plain')) {
      // 当作错误处理, 读取 body 给用户看
      final errBody = await response.transform(utf8.decoder).join();
      throw Exception('HTTP ${response.statusCode}: $errBody');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      _requireWorkspace(revision);
      bytes.addAll(chunk);
    }
    _requireWorkspace(revision);
    // 从 Content-Disposition 提取文件名
    final cd = response.headers.value('content-disposition') ?? '';
    String filename = 'export';
    final match = RegExp(r'filename=([^;\s]+)').firstMatch(cd);
    if (match != null) {
      filename = Uri.decodeFull(match.group(1)!.replaceAll('"', ''));
    } else {
      filename =
          contentType.contains('wordprocessingml')
              ? 'export.docx'
              : 'export.txt';
    }
    return (bytes: bytes, filename: filename);
  }

  /// DELETE 请求
  Future<ApiResponse> delete(String path, {Map<String, dynamic>? body}) async {
    return _request('DELETE', path, body: body);
  }

  /// 通用 HTTP 请求
  Future<ApiResponse> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    _requireWorkspace();
    final revision = localDataSource.sessionRevision;
    for (var attempt = 0; attempt < 2; attempt++) {
      _requireWorkspace(revision);
      final resp = await _doRequest(method, path, body: body);
      _requireWorkspace(revision);
      // 401: 可能是 token 失效, 重新拉取一次
      if (resp.code == 401 && attempt == 0) {
        try {
          await init();
        } catch (_) {
          _requireWorkspace(revision);
          return resp;
        }
        _requireWorkspace(revision);
        continue;
      }
      return resp;
    }
    throw Exception('请求重试耗尽: $method $path');
  }

  Future<ApiResponse> _doRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    _requireWorkspace();
    final revision = localDataSource.sessionRevision;
    final uri = Uri.parse('$_baseUrl$path');
    HttpClientRequest request;
    switch (method) {
      case 'POST':
        request = await _httpClient.postUrl(uri);
        break;
      case 'PUT':
        request = await _httpClient.putUrl(uri);
        break;
      case 'DELETE':
        request = await _httpClient.deleteUrl(uri);
        break;
      default:
        request = await _httpClient.getUrl(uri);
    }

    _requireWorkspace(revision);
    _attachHeaders(request);

    if (body != null) {
      request.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      request.write(jsonEncode(body));
    }

    final response = await request.close();
    _requireWorkspace(revision);
    _checkBindingResponse(response);
    final responseBody = await response.transform(utf8.decoder).join();
    _requireWorkspace(revision);
    final json = jsonDecode(responseBody) as Map<String, dynamic>;
    // D37 Phase 1-7: 后端 /api/commands 返回 {"code":0,"data":[...]} (List data)
    // ApiResponse.fromJson 会丢弃 List, 这里自动检测并用 listFromJson 包装
    if (json['data'] is List) {
      return ApiResponse.listFromJson(json);
    }
    return ApiResponse.fromJson(json);
  }

  /// SSE 流式请求，返回 token 流 (兼容旧调用: 仅 yield content)
  /// T-7: SSE reasoning 全链路修复 — 旧接口保留, 新代码用 ssePostEvents 拿结构化事件
  Stream<String> ssePost(String path, {Map<String, dynamic>? body}) async* {
    await for (final evt in ssePostEvents(path, body: body)) {
      if (evt.type == SseEventType.content) {
        yield evt.content;
      }
    }
  }

  /// SSE 流式请求 — 结构化事件流 (T-7)
  ///
  /// 事件类型:
  /// - content: 普通内容 chunk
  /// - reasoning: V4 推理内容 (CoT, 与 content 互斥)
  /// - warning: 后端警告 (例如 lore 未压缩)
  /// - error: API/网络错误
  /// - done: 流结束
  Stream<SseEvent> ssePostEvents(
    String path, {
    Map<String, dynamic>? body,
    bool requireComplete = false,
    void Function(Map<String, dynamic>)? onReceipt,
  }) async* {
    _requireWorkspace();
    final revision = localDataSource.sessionRevision;
    final uri = Uri.parse('$_baseUrl$path');
    // A stream owns its connection so cancellation/timeout never closes
    // unrelated requests on the shared client.
    final streamClient =
        HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await streamClient.postUrl(uri);
      _requireWorkspace(revision);
      _attachHeaders(request);
      request.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      request.headers.set('Accept', 'text/event-stream');

      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(
        const Duration(seconds: 90),
      );
      _requireWorkspace(revision);
      _checkBindingResponse(response);
      if (response.statusCode != 200) {
        final errBody = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 15));
        throw HttpException('SSE 请求失败 (${response.statusCode}): $errBody');
      }

      String buffer = '';
      await for (final chunk in response
          .transform(utf8.decoder)
          .timeout(const Duration(seconds: 90))) {
        _requireWorkspace(revision);
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast(); // 保留未完成的行

        for (final line in lines) {
          _requireWorkspace(revision);
          final trimmed = line.trim();
          if (trimmed.startsWith('data:')) {
            final data = trimmed.substring(5).trimLeft();
            if (data.isEmpty) continue;
            if (data == '[DONE]') {
              yield const SseEvent(type: SseEventType.done);
              return;
            }
            // 尝试解析 JSON 格式的 SSE data
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              if (json['type'] == 'receipt') {
                onReceipt?.call(json);
                continue;
              }
              // T-7: 识别后端透传的 reasoning/error/stopped 裸 JSON
              // (deepseek.py stream_chat 产出: {"reasoning":"..."} / {"error":"..."} / {"stopped":true})
              final reasoning = json['reasoning'] as String?;
              if (reasoning != null) {
                yield SseEvent(
                  type: SseEventType.reasoning,
                  content: reasoning,
                );
                continue;
              }
              final err = json['error'] as String?;
              if (err != null) {
                yield SseEvent(type: SseEventType.error, content: err);
                continue;
              }
              if (json['stopped'] == true) {
                yield requireComplete
                    ? const SseEvent(
                      type: SseEventType.error,
                      content: '生成已停止，回复未完成。',
                    )
                    : const SseEvent(type: SseEventType.done);
                return;
              }
              // ShuFang 后端包装: {"type": "content", "content": "chunk"}
              //                  {"type": "reasoning", "content": "..."}  (理论上不会出现, deepseek 透传裸 JSON)
              //                  {"type": "warning", "message": "..."}
              //                  {"type": "error_api", "message": "..."}
              final type = json['type'] as String?;
              if (type == 'content') {
                yield SseEvent(
                  type: SseEventType.content,
                  content: json['content'] as String? ?? '',
                );
                continue;
              }
              if (type == 'reasoning') {
                yield SseEvent(
                  type: SseEventType.reasoning,
                  content: json['content'] as String? ?? '',
                );
                continue;
              }
              if (type == 'warning') {
                yield SseEvent(
                  type: SseEventType.warning,
                  content: json['message'] as String? ?? '',
                );
                continue;
              }
              if (type == 'error_api' ||
                  type == 'error' ||
                  type == 'error_auth') {
                yield SseEvent(
                  type: SseEventType.error,
                  content: json['message'] as String? ?? '',
                );
                continue;
              }
              // OpenAI 兼容: {"delta": {"content": "chunk"}} 或 {"delta": "chunk"}
              final delta = json['delta'];
              if (delta is String) {
                yield SseEvent(type: SseEventType.content, content: delta);
                continue;
              } else if (delta is Map<String, dynamic>) {
                final dContent = delta['content'] as String?;
                if (dContent != null) {
                  yield SseEvent(type: SseEventType.content, content: dContent);
                  continue;
                }
              }
              // 通用: {"content": "chunk"} 或 {"text": "chunk"}
              final content = json['content'] as String?;
              if (content != null) {
                yield SseEvent(type: SseEventType.content, content: content);
                continue;
              }
              final text = json['text'] as String?;
              if (text != null) {
                yield SseEvent(type: SseEventType.content, content: text);
              }
            } catch (_) {
              if (requireComplete) {
                yield const SseEvent(
                  type: SseEventType.error,
                  content: '收到无法解析的生成数据，回复未完成。',
                );
                return;
              }
              // 纯文本 data
              if (data.isNotEmpty) {
                yield SseEvent(type: SseEventType.content, content: data);
              }
            }
          }
        }
      }
      if (requireComplete) {
        throw const HttpException('连接在完成标记前结束，回复未完成。');
      }
      yield const SseEvent(type: SseEventType.done);
    } finally {
      streamClient.close(force: true);
    }
  }

  /// 附加认证头
  void _attachHeaders(HttpClientRequest request) {
    request.followRedirects = false;
    if (_token != null) {
      request.headers.set('X-ShuFang-Token', _token!);
    }
    if (_capabilities != null) {
      request.headers.set('X-ShuFang-Workspace', _capabilities!.workspaceId);
      request.headers.set('X-ShuFang-Instance', _capabilities!.instanceId);
    }
  }

  // ============================================================
  // D43: LLM 运营商管理 API
  // ============================================================

  /// GET /api/llm/providers — 列出所有运营商 + 配置状态
  Future<LlmProvidersResponse> getLlmProviders() async {
    final resp = await get(ApiRoutes.llmProviders);
    if (!resp.ok || resp.data == null) {
      throw Exception(resp.message.isEmpty ? '获取运营商列表失败' : resp.message);
    }
    return LlmProvidersResponse.fromJson(resp.data!);
  }

  /// POST /api/llm/config — 保存某运营商运行时配置
  ///
  /// 返回 {ok, provider, configured, available_providers}
  Future<Map<String, dynamic>> saveLlmConfig({
    required String provider,
    required String apiKey,
    String baseUrl = '',
    String defaultModel = '',
  }) async {
    final resp = await post(
      ApiRoutes.llmConfig,
      body: {
        'provider': provider,
        'api_key': apiKey,
        'base_url': baseUrl,
        'default_model': defaultModel,
      },
    );
    if (!resp.ok || resp.data == null) {
      throw Exception(resp.message.isEmpty ? '保存配置失败' : resp.message);
    }
    return resp.data!;
  }

  /// POST /api/llm/test — 测试某运营商连通性
  Future<LlmTestResult> testLlmProvider({
    required String provider,
    String apiKey = '',
    String baseUrl = '',
    String model = '',
  }) async {
    final resp = await post(
      ApiRoutes.llmTest,
      body: {
        'provider': provider,
        'api_key': apiKey,
        'base_url': baseUrl,
        'model': model,
      },
    );
    if (!resp.ok || resp.data == null) {
      throw Exception(resp.message.isEmpty ? '测试失败' : resp.message);
    }
    return LlmTestResult.fromJson(resp.data!);
  }

  /// POST /api/llm/switch — 切换默认运营商
  Future<void> switchLlmProvider(String provider) async {
    final resp = await post(ApiRoutes.llmSwitch, body: {'provider': provider});
    if (!resp.ok) {
      throw Exception(resp.message.isEmpty ? '切换运营商失败' : resp.message);
    }
  }

  /// DELETE /api/llm/config/{provider} — 清除某运营商运行时配置
  Future<void> clearLlmConfig(String provider) async {
    final resp = await delete(ApiRoutes.llmConfigOf(provider));
    if (!resp.ok) {
      throw Exception(resp.message.isEmpty ? '清除配置失败' : resp.message);
    }
  }
}

/// SSE 事件类型枚举 (T-7)
enum SseEventType {
  content, // 普通内容 chunk
  reasoning, // V4 推理内容 (CoT)
  warning, // 后端警告
  error, // API/网络错误
  done, // 流结束
}

/// SSE 结构化事件 (T-7)
class SseEvent {
  final SseEventType type;
  final String content;

  const SseEvent({required this.type, this.content = ''});

  @override
  String toString() => 'SseEvent(${type.name}: ${content.length} chars)';
}

/// 全局 API 客户端实例
final apiClient = ApiClient();
