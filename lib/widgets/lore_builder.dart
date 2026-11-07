import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/api_routes.dart';

/// 索引构建组件 (简化版，用于侧边栏嵌入)
class LoreBuilder extends StatefulWidget {
  const LoreBuilder({super.key});

  @override
  State<LoreBuilder> createState() => _LoreBuilderState();
}

class _LoreBuilderState extends State<LoreBuilder> {
  bool _building = false;
  String _status = '';
  String _statusState = 'idle';
  int _progress = 0;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final res = await apiClient.get(ApiRoutes.loreBuildStatus);
      // E 阶段修复 P1-1: 后端返回 {"status": {"state": "...", "stats": {"total_chunks": N}}}
      // 之前误读顶层 total_chunks → 永远 null
      final status = res.data?['status'] as Map<String, dynamic>?;
      setState(() {
        _statusState = status?['state'] as String? ?? 'idle';
        _progress = (status?['progress'] as num?)?.toInt() ?? 0;
        _stats = status?['stats'] as Map<String, dynamic>?;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设定索引', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_stats != null) ...[
            Text('已索引: ${_stats!['total_chunks'] ?? 0} 个分块',
                style: Theme.of(context).textTheme.bodyMedium),
            Text('压缩比: ${_stats!['compression_ratio'] ?? '-'}x'
                '  分组: ${(_stats!['groups'] as List?)?.length ?? 0}',
                style: Theme.of(context).textTheme.bodyMedium),
          ] else if (_statusState == 'building') ...[
            Text('构建中... $_progress%',
                style: Theme.of(context).textTheme.bodyMedium),
          ] else ...[
            Text('索引未构建', style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _building ? null : _buildIndex,
              child: _building
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('构建索引'),
            ),
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_status, style: Theme.of(context).textTheme.labelSmall),
          ],
        ],
      ),
    );
  }

  Future<void> _buildIndex() async {
    setState(() {
      _building = true;
      _status = '构建中...';
      _statusState = 'building';
      _progress = 0;
    });
    try {
      // E 阶段修复: /api/lore/build 返回 {"status": "started", "build_id": "..."}
      // 不直接返回 stats, 需要轮询 /status 获取进度
      await apiClient.post(ApiRoutes.loreBuild, body: {'type': 'full'});
      setState(() {
        _status = '构建已启动，轮询进度...';
      });
      // 轮询状态直到完成或超时
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(seconds: 2));
        await _loadStats();
        if (_statusState == 'completed' || _statusState == 'failed') break;
      }
      setState(() {
        _status = _statusState == 'completed'
            ? '构建完成: ${_stats?['total_chunks'] ?? 0} 个分块'
            : _statusState == 'failed'
                ? '构建失败'
                : '构建超时，请稍后查看状态';
        _building = false;
      });
    } catch (e) {
      setState(() {
        _status = '构建失败: $e';
        _building = false;
        _statusState = 'failed';
      });
    }
  }
}
