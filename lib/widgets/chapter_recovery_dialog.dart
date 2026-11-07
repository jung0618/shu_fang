import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/chapter_recovery.dart';
import '../services/chapter_save_queue.dart';
import '../services/editor_request_lease.dart';
import '../services/safe_file_writer.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';

class ChapterRecoveryDialog extends ConsumerStatefulWidget {
  const ChapterRecoveryDialog({super.key});

  @override
  ConsumerState<ChapterRecoveryDialog> createState() =>
      _ChapterRecoveryDialogState();
}

class _ChapterRecoveryDialogState extends ConsumerState<ChapterRecoveryDialog> {
  late final EditorRequestLease _lease;
  late final Future<ChapterPreviousVersion?> _previous;
  late final String _currentText;
  bool _restoring = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lease = EditorRequestLease(ref);
    _currentText = ref.read(editorTextProvider);
    _previous = ChapterRecovery.readPrevious(
      ChapterAddress(
        localDataSource.storageRoot,
        _lease.book!,
        _lease.chapter!,
      ),
    );
  }

  Future<void> _restore(ChapterPreviousVersion previous) async {
    if (_restoring || !_lease.isCurrent) return;
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(Duration.zero);
      if (!_lease.isCurrent) return;
      if (!await chapterSaveQueue.flushAll()) {
        throw StateError('当前正文或标记未保存，恢复已停止。请先处理保存失败。');
      }
      await SafeFileWriter.flushAll();
      if (!mounted || !_lease.isCurrent) return;
      ref.read(pendingChapterRestoreProvider.notifier).state = (
        address: previous.address,
        text: previous.text,
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!_lease.isCurrent) return;
      setState(() {
        _restoring = false;
        _error = '恢复失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ChapterPreviousVersion?>(
      future: _previous,
      builder: (context, snapshot) {
        final previous = snapshot.data;
        return AlertDialog(
          title: Text('查看上一版 · ${_lease.chapter}'),
          content: SizedBox(
            width: 800,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('仅保留最近一次保存前的正文。恢复会先保存当前稿，再替换正文并清空当前标记。'),
                const SizedBox(height: 12),
                if (snapshot.connectionState != ConnectionState.done)
                  const Center(child: CircularProgressIndicator())
                else if (snapshot.hasError)
                  Text('无法读取上一版：${snapshot.error}')
                else if (previous == null)
                  const Text('暂无上一版。章节再次保存后，这里会保留保存前的正文。')
                else ...[
                  Text(
                    '上一版记录时间：${previous.capturedAt.toLocal().toString().split('.').first}',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.44,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final current = _Preview(
                          title: '当前正文',
                          text: _currentText,
                        );
                        final earlier = _Preview(
                          title: '上一版正文',
                          text: previous.text,
                        );
                        return constraints.maxWidth < 600
                            ? Column(
                              children: [
                                Expanded(child: current),
                                const SizedBox(height: 8),
                                Expanded(child: earlier),
                              ],
                            )
                            : Row(
                              children: [
                                Expanded(child: current),
                                const SizedBox(width: 12),
                                Expanded(child: earlier),
                              ],
                            );
                      },
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _restoring ? null : () => Navigator.of(context).pop(),
              child: const Text('保留当前稿'),
            ),
            FilledButton(
              onPressed:
                  previous == null || _restoring
                      ? null
                      : () => _restore(previous),
              child: Text(_restoring ? '正在保存当前稿…' : '恢复上一版'),
            ),
          ],
        );
      },
    );
  }
}

class _Preview extends StatelessWidget {
  final String title;
  final String text;
  const _Preview({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(text.isEmpty ? '（空白正文）' : text),
            ),
          ),
        ],
      ),
    );
  }
}
