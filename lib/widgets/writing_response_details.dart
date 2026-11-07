import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/writing_request_ledger.dart';
import '../services/writing_response_store.dart';
import '../store/local_data_source.dart';

typedef WritingResponseLoader =
    Future<WritingResponseSnapshot> Function({
      required String root,
      required WritingRequestRecord record,
    });

/// Explicit, read-only access to a completed response stored for this request.
class WritingResponseDetails extends StatefulWidget {
  final String root;
  final WritingRequestRecord record;
  final WritingResponseLoader? loader;

  const WritingResponseDetails({
    super.key,
    required this.root,
    required this.record,
    this.loader,
  });

  @override
  State<WritingResponseDetails> createState() => _WritingResponseDetailsState();
}

class _WritingResponseDetailsState extends State<WritingResponseDetails> {
  late int _sessionRevision;
  int _operation = 0;
  WritingResponseSnapshot? _snapshot;
  bool _loading = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _sessionRevision = localDataSource.sessionRevision;
  }

  @override
  void didUpdateWidget(covariant WritingResponseDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.root != widget.root ||
        oldWidget.record.id != widget.record.id ||
        !identical(oldWidget.record, widget.record) ||
        oldWidget.loader != widget.loader) {
      _operation++;
      _snapshot = null;
      _loading = false;
      _message = null;
      _sessionRevision = localDataSource.sessionRevision;
    }
  }

  bool get _isCurrent =>
      mounted &&
      _sessionRevision == localDataSource.sessionRevision &&
      widget.root == localDataSource.storageRoot;

  Future<void> _read() async {
    if (!_isCurrent) {
      setState(() => _message = '工作区已切换，请关闭后重新查看。');
      return;
    }
    final operation = ++_operation;
    setState(() {
      _loading = true;
      _message = null;
      _snapshot = null;
    });
    try {
      final snapshot = await (widget.loader ??
          WritingResponseStore.readCompleted)(
        root: widget.root,
        record: widget.record,
      );
      if (!_isCurrent || operation != _operation) return;
      setState(() => _snapshot = snapshot);
    } catch (_) {
      if (!_isCurrent || operation != _operation) return;
      setState(() => _message = '暂时无法读取本机回复；原记录未更改。');
    } finally {
      if (mounted && operation == _operation) setState(() => _loading = false);
    }
  }

  Future<void> _copy() async {
    final snapshot = _snapshot;
    if (!_isCurrent || snapshot == null || !snapshot.canCopy || _loading) {
      setState(() => _message = '工作区或回复状态已变化，请重新读取后再复制。');
      return;
    }
    final operation = _operation;
    try {
      await Clipboard.setData(ClipboardData(text: snapshot.body!));
      if (!_isCurrent || operation != _operation || !mounted) return;
      setState(() => _message = '回复已复制');
    } catch (_) {
      if (_isCurrent && operation == _operation && mounted) {
        setState(() => _message = '复制失败；回复仍保留在本机记录中。');
      }
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: localDataSource.sessionChanges,
    builder: (context, revision, child) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = _isCurrent ? _snapshot : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          Text('本机回复正文', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '只读查看 · 模型候选内容 · 未写入原稿、偏好或训练资料',
            style: theme.textTheme.bodySmall,
          ),
          if (snapshot?.canCopy == true) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: SelectableText(snapshot!.body!),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _copy,
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('复制回复'),
              ),
            ),
          ] else if (snapshot != null) ...[
            const SizedBox(height: 8),
            Text(snapshot.message, style: theme.textTheme.bodyMedium),
          ] else if (_snapshot != null && !_isCurrent) ...[
            const SizedBox(height: 8),
            const Text('工作区已切换，请关闭后重新查看。'),
          ],
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(_message!, style: theme.textTheme.bodyMedium),
          ],
          if (_loading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loading ? null : _read,
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: Text(_loading ? '正在读取…' : '查看本机回复'),
            ),
          ),
        ],
      ),
    );
  }
}
