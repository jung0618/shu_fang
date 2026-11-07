import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/api_routes.dart';

/// 就绪状态检查组件 (简化版，用于侧边栏嵌入)
class ReadinessChecker extends StatefulWidget {
  const ReadinessChecker({super.key});

  @override
  State<ReadinessChecker> createState() => _ReadinessCheckerState();
}

class _ReadinessCheckerState extends State<ReadinessChecker> {
  Map<String, dynamic>? _result;
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('就绪检查', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _checking ? null : _check,
              child: _checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('检查'),
            ),
          ),
          if (_result != null) ...[
            const SizedBox(height: 12),
            ..._buildCheckItems(),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildCheckItems() {
    // D37 Phase 0-5: error 键渲染为错误态卡片, 不再静默
    final errMsg = _result?['error'] as String?;
    if (errMsg != null) {
      return [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFC92A2A).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFC92A2A).withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 18, color: Color(0xFFC92A2A)),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  errMsg,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ];
    }
    final checks = _result?['checks'] as Map<String, dynamic>? ?? {};
    return checks.entries.map((entry) {
      final passed = entry.value == true;
      return Row(
        children: [
          Icon(
            passed ? Icons.check_circle : Icons.error,
            size: 16,
            color: passed ? const Color(0xFF2B8A3E) : const Color(0xFFC92A2A),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(entry.key, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      );
    }).toList();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final res = await apiClient.get(ApiRoutes.readinessCheck);
      // D38: 校验 res.ok, 引擎报错不再静默显示空结果
      if (!res.ok) {
        setState(() => _result = {'error': res.message.isEmpty ? '引擎就绪检查失败 (code=${res.code})' : res.message});
      } else {
        setState(() => _result = res.data);
      }
    } catch (e) {
      setState(() => _result = {'error': e.toString()});
    } finally {
      setState(() => _checking = false);
    }
  }
}
