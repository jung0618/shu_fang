import '../api/api_client.dart';
import '../api/api_routes.dart';
import '../store/local_data_source.dart';

/// Read-only server evidence, separate from local receipt and provider billing.
class EngineRequestStatus {
  final String requestId;
  final String inputSha256;
  final String state;
  final bool ownerIsCurrentInstance;
  const EngineRequestStatus._(
    this.requestId,
    this.inputSha256,
    this.state,
    this.ownerIsCurrentInstance,
  );

  factory EngineRequestStatus.fromJson(
    Map<String, dynamic> json, {
    required String requestId,
  }) {
    if (json['schema_version'] != 1 ||
        json['request_id'] != requestId ||
        !RegExp(r'^\d{16}-[a-f0-9]{32}$').hasMatch(requestId) ||
        json['input_sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(json['input_sha256']) ||
        !const {
          'admitted',
          'dispatching',
          'completed',
          'failed',
          'interrupted',
        }.contains(json['state']) ||
        json['owner_is_current_instance'] is! bool ||
        json['retry_allowed'] != false ||
        json['settlement'] != 'unknown') {
      throw const FormatException('引擎记录格式不兼容，请保留本地记录核查。');
    }
    return EngineRequestStatus._(
      requestId,
      json['input_sha256'] as String,
      json['state'] as String,
      json['owner_is_current_instance'] as bool,
    );
  }

  String get description => switch (state) {
    'completed' => '引擎已收齐回复；本地是否保存，请结合本地记录核查。',
    'failed' => '引擎未完成回复；结算状态未知。',
    'interrupted' => '引擎接收已中断；供应商是否停止、费用多少仍待核查。',
    _ => '引擎未见完成记录；不会自动重新调用模型。',
  };

  static Future<EngineRequestStatus> lookup(
    String requestId, {
    ApiClient? client,
  }) async {
    final api = client ?? apiClient;
    final binding = api.capabilities;
    if (!api.supports('request_ledger')) {
      throw StateError('请先连接支持调用记录核查的当前工作区引擎。');
    }
    if (!RegExp(r'^\d{16}-[a-f0-9]{32}$').hasMatch(requestId)) {
      throw const FormatException('请求编号无效。');
    }
    final revision = localDataSource.sessionRevision;
    final response = await api
        .get(ApiRoutes.engineRequest(requestId))
        .timeout(const Duration(seconds: 8));
    if (revision != localDataSource.sessionRevision ||
        !identical(binding, api.capabilities)) {
      throw StateError('工作区或引擎连接已切换，原核查结果已丢弃。');
    }
    if (!response.ok || response.data == null) {
      throw StateError(
        response.code == 404
            ? '引擎未找到该编号；这不能证明请求未发送或费用为零。'
            : '暂时无法核查引擎记录；请保留本地记录，不要直接重复生成。',
      );
    }
    return EngineRequestStatus.fromJson(response.data!, requestId: requestId);
  }
}
