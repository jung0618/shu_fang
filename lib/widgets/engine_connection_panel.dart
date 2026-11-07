import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../services/engine_launcher.dart';

/// Shared by every workspace, regardless of legacy build flavor.
class EngineConnectionPanel extends ConsumerWidget {
  const EngineConnectionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(engineStatusProvider);
    ref.watch(engineBindingProvider);
    final message = ref.watch(engineMessageProvider);
    final capabilities = apiClient.capabilities;
    final connected = status == EngineStatus.ready && capabilities != null;
    final busy = status == EngineStatus.starting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          connected
              ? '已连接当前工作区'
              : busy
              ? '正在核对连接…'
              : '引擎尚未连接',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        const Text('本地写作随时可用。AI 辅助还需配置模型服务，是否可用以实际请求结果为准。'),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(message, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : () => EngineLauncher.startEngine(ref),
              icon: const Icon(Icons.power_settings_new, size: 16),
              label: Text(connected ? '重新连接' : '启动并连接'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => EngineLauncher.probeEngine(ref),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('检查连接'),
            ),
          ],
        ),
        if (connected) ...[
          const SizedBox(height: 12),
          Text(
            capabilities.supports('context_feedback')
                ? '写作上下文接口：已接入（模型未验证）'
                : '写作上下文接口：暂不可用',
          ),
          Text(
            capabilities.supports('training_status')
                ? '训练状态：可查询（不代表训练正在运行）'
                : '训练状态：暂不可查询',
          ),
          const Text('训练启动与快照：尚未接入'),
          const Text('向量检索：尚未验证'),
        ],
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('连接详情'),
          children: [
            SelectableText('本机地址：${apiClient.endpointDescription}'),
            if (connected) SelectableText('引擎目录：${capabilities.workspaceRoot}'),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('找不到配套引擎时，可按安装说明配置位置。地址被占用或目录不匹配时，请先核对已有服务。'),
            ),
          ],
        ),
      ],
    );
  }
}
