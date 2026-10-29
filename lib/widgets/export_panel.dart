import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_routes.dart';
import '../services/chapter_save_queue.dart';
import '../services/editor_request_lease.dart';
import '../services/local_book_exporter.dart';
import '../services/safe_file_writer.dart';
import '../store/editor_store.dart';
import '../store/workspace_store.dart';
import '../theme/theme.dart';

class ExportPanel extends ConsumerStatefulWidget {
  const ExportPanel({super.key});

  @override
  ConsumerState<ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends ConsumerState<ExportPanel> {
  String _status = '';
  String? _savedPath;
  bool _exporting = false;

  Future<void> _export({LocalExportFormat? format}) async {
    if (_exporting) return;
    final lease = EditorRequestLease(ref);
    final book = lease.book;
    if (book == null) return;
    final root = ref.read(storageRootProvider);
    setState(() {
      _exporting = true;
      _savedPath = null;
      _status = '正在保存当前稿并导出…';
    });
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(Duration.zero);
      if (!lease.isCurrent) return;
      if (!await chapterSaveQueue.flushAll()) {
        throw StateError('正文或标记还有保存失败，导出已停止。请先保存后重试。');
      }
      await SafeFileWriter.flushAll();
      if (!lease.isCurrent) return;
      final String path;
      if (format != null) {
        final snapshot = await LocalBookExporter.capture(
          root: root,
          book: book,
          sessionRevision: lease.revision,
        );
        if (!lease.isCurrent) return;
        path = await LocalBookExporter.save(
          snapshot,
          format,
          sessionRevision: lease.revision,
        );
      } else {
        final result = await apiClient.downloadFile(
          ApiRoutes.exportDocx,
          body: {'book': book},
        );
        if (!lease.isCurrent) return;
        // Never use an untrusted response filename as a filesystem path.
        path =
            File(
              '$root/exports/$book-${DateTime.now().microsecondsSinceEpoch}.docx',
            ).absolute.path;
        await SafeFileWriter.writeBytes(path, result.bytes);
      }
      if (!lease.isCurrent) return;
      setState(() {
        _savedPath = path;
        _status = '导出完成，已生成新的文件：$path';
      });
    } catch (error) {
      if (lease.isCurrent) setState(() => _status = '导出失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          if (!lease.isCurrent) _status = '编辑位置已切换，请重新导出当前作品。';
        });
      }
    }
  }

  Future<void> _openFolder() async {
    final path = _savedPath;
    if (path == null) return;
    try {
      final folder = File(path).parent.path;
      final result =
          Platform.isWindows
              ? await Process.run('explorer.exe', [folder])
              : Platform.isMacOS
              ? await Process.run('open', [folder])
              : await Process.run('xdg-open', [folder]);
      // Windows Explorer may return 1 when reusing an existing window.
      if (!Platform.isWindows && result.exitCode != 0) {
        throw StateError('无法打开文件夹，请复制上方路径。');
      }
    } catch (error) {
      if (mounted && path == _savedPath) {
        setState(() => _status = '文件已导出，但无法打开文件夹：$error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentBookProvider, (_, __) {
      setState(() {
        _savedPath = null;
        _status = '';
      });
    });
    final brightness = Theme.of(context).brightness;
    final book = ref.watch(currentBookProvider);
    final workspace = ref.watch(currentWorkspaceProvider);
    final available = book != null && !_exporting;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('导出作品', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: S.sm),
          Text(book == null ? '先打开一部作品，再来导出。' : '当前作品：$book'),
          const SizedBox(height: S.md),
          const Text(
            'TXT 和 Markdown 可离线导出全部章节，按章节列表顺序排列。正文中的标点、段落和 Markdown 标记保留原样。',
          ),
          const SizedBox(height: S.sm),
          const Text('文件保存在当前工作区的 exports 文件夹；每次生成新文件，导出过程中的后续修改可能未包含在本次文件中。'),
          const SizedBox(height: S.lg),
          Wrap(
            spacing: S.sm,
            runSpacing: S.sm,
            children: [
              FilledButton.tonalIcon(
                onPressed:
                    available
                        ? () => _export(format: LocalExportFormat.txt)
                        : null,
                icon: const Icon(Icons.text_snippet_outlined),
                label: const Text('离线 TXT'),
              ),
              FilledButton.tonalIcon(
                onPressed:
                    available
                        ? () => _export(format: LocalExportFormat.markdown)
                        : null,
                icon: const Icon(Icons.article_outlined),
                label: const Text('离线 Markdown'),
              ),
              if (workspace?.isPrimary == true)
                OutlinedButton.icon(
                  onPressed: available ? () => _export() : null,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('DOCX · 需连接服务'),
                ),
            ],
          ),
          if (_exporting) ...[
            const SizedBox(height: S.md),
            const LinearProgressIndicator(),
          ],
          if (_status.isNotEmpty) ...[
            const SizedBox(height: S.lg),
            Container(
              padding: const EdgeInsets.all(S.md),
              decoration: BoxDecoration(
                color: AppPalette.surfaceHigh(brightness),
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: SelectableText(_status),
            ),
          ],
          if (_savedPath != null) ...[
            const SizedBox(height: S.sm),
            TextButton.icon(
              onPressed: _openFolder,
              icon: const Icon(Icons.folder_open),
              label: const Text('打开导出文件夹'),
            ),
          ],
        ],
      ),
    );
  }
}
