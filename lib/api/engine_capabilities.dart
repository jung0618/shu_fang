import 'dart:io';

class EngineCapability {
  final bool available;
  final String reason;
  const EngineCapability(this.available, this.reason);
}

/// An authenticated description of implemented routes, never a model readiness receipt.
class EngineCapabilities {
  final String instanceId;
  final String workspaceId;
  final String workspaceRoot;
  final Map<String, EngineCapability> capabilities;
  EngineCapabilities._(
    this.instanceId,
    this.workspaceId,
    this.workspaceRoot,
    Map<String, EngineCapability> capabilities,
  ) : capabilities = Map.unmodifiable(capabilities);

  factory EngineCapabilities.fromJson(Map<String, dynamic> json) {
    if (json['product'] != 'shufang' ||
        json['protocol_version'] is! int ||
        json['protocol_version'] != 1 ||
        json['instance_id'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(json['instance_id'] as String) ||
        json['workspace_id'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(json['workspace_id'] as String) ||
        json['workspace_root'] is! String ||
        !Directory(json['workspace_root'] as String).isAbsolute ||
        json['capabilities'] is! Map<String, dynamic>) {
      throw const FormatException('引擎未提供兼容的身份和工作区信息，请更新引擎。');
    }
    final parsed = <String, EngineCapability>{};
    for (final entry
        in (json['capabilities'] as Map<String, dynamic>).entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic> ||
          value['available'] is! bool ||
          value['reason'] is! String) {
        throw const FormatException('引擎能力信息不完整。');
      }
      parsed[entry.key] = EngineCapability(
        value['available'] as bool,
        value['reason'] as String,
      );
    }
    return EngineCapabilities._(
      json['instance_id'] as String,
      json['workspace_id'] as String,
      json['workspace_root'] as String,
      parsed,
    );
  }

  bool supports(String name) => capabilities[name]?.available == true;

  static Future<String> canonicalRoot(String root) async {
    final path = await Directory(root).resolveSymbolicLinks();
    return Platform.isWindows ? path.toLowerCase() : path;
  }
}
