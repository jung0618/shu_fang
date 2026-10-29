import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_routes.dart';

/// 增量更新索引对话框
class IncrementalIndexDialog extends ConsumerStatefulWidget {
  const IncrementalIndexDialog({super.key});

  @override
  ConsumerState<IncrementalIndexDialog> createState() => _IncrementalIndexDialogState();
}

class _IncrementalIndexDialogState extends ConsumerState<IncrementalIndexDialog> {
  bool _busy = false;
  String? _result;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      // D37 Phase 1-5: 后端 /api/index/incremental 不存在
      // 改调 /api/lore/build 带 type=incremental (后端 lore.py 已支持 auto|full|incremental)
      final res = await apiClient.post(ApiRoutes.loreBuild, body: {
        'type': 'incremental',
      });
      if (!mounted) return;
      if (res.ok) {
        final buildId = res.data?['build_id'] as String?;
        final status = res.data?['status'] as String? ?? 'started';
        setState(() {
          _result = '索引构建已启动 (status=$status${buildId != null ? ", build_id=$buildId" : ""})';
        });
      } else {
        setState(() {
          _result = '失败: ${res.message.isEmpty ? "未知错误 (code=${res.code})" : res.message}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _result = '失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('增量更新索引'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('仅扫描新增/修改的章节与设定文件，刷新向量索引与单元集缓存。'),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            if (_result != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_result!, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: _busy ? null : _run,
          child: const Text('开始更新'),
        ),
      ],
    );
  }
}
