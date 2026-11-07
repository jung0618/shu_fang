import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_routes.dart';
import '../store/editor_store.dart';

/// 新建单元集对话框
class UnitSetCreateDialog extends ConsumerStatefulWidget {
  const UnitSetCreateDialog({super.key});

  @override
  ConsumerState<UnitSetCreateDialog> createState() => _UnitSetCreateDialogState();
}

class _UnitSetCreateDialogState extends ConsumerState<UnitSetCreateDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '名称不能为空');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await apiClient.post(ApiRoutes.unitSets, body: {
        'name': name,
        'description': _descController.text.trim(),
      });
      if (mounted) {
        if (res.ok) {
          ref.invalidate(unitSetsProvider);
          Navigator.of(context).pop();
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
      title: const Text('新建单元集'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '描述 (可选)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: const Text('创建'),
        ),
      ],
    );
  }
}
