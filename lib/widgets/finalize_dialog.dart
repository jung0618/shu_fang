import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_routes.dart';

/// 定档对话框：检查 + 输出风格报告 + 标记为定稿
class FinalizeDialog extends ConsumerStatefulWidget {
  final String book;
  final String chapter;
  const FinalizeDialog({super.key, required this.book, required this.chapter});

  @override
  ConsumerState<FinalizeDialog> createState() => _FinalizeDialogState();
}

class _FinalizeDialogState extends ConsumerState<FinalizeDialog> {
  bool _busy = false;
  Map<String, dynamic>? _checkResult;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await apiClient.get(
        ApiRoutes.styleCheck(widget.book, widget.chapter),
      );
      if (mounted) {
        // D38: 校验 res.ok, 引擎错误不渲染假结果
        if (res.ok) {
          setState(() => _checkResult = res.data);
        } else {
          setState(() => _error = res.message.isEmpty ? '风格检查失败 (code=${res.code})' : res.message);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finalize() async {
    setState(() => _busy = true);
    try {
      final res = await apiClient.post(
        ApiRoutes.styleFinalize(widget.book, widget.chapter),
        body: {'confirmed': true},
      );
      if (mounted) {
        if (res.ok) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已定档')),
          );
        } else {
          setState(() => _error = res.message);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('定档'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              if (_checkResult != null) ...[
                const SizedBox(height: 12),
                _ResultRow(label: '一致性评分', value: _checkResult!['consistency']),
                _ResultRow(label: '重复度', value: _checkResult!['repetition']),
                _ResultRow(label: '对话占比', value: _checkResult!['dialogue_ratio']),
                _ResultRow(label: '建议字数', value: _checkResult!['suggested_length']),
                const SizedBox(height: 12),
                Text('章节总字符: ${_checkResult!['chars'] ?? '-'}',
                    style: const TextStyle(fontSize: 12)),
              ],
              const SizedBox(height: 12),
              const Text('定档后将锁定正文，标记为终稿', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy || _checkResult == null ? null : _finalize,
          child: const Text('确认定档'),
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final dynamic value;
  const _ResultRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value?.toString() ?? '-',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
