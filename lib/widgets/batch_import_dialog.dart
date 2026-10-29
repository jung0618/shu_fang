import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';

/// 批量章节导入对话框
///
/// **使用方式**：选择一个文件夹，自动扫描其中的 .txt / .md 文件，
/// 用户勾选要导入的章节，确认后批量创建。
class BatchImportDialog extends ConsumerStatefulWidget {
  final String bookId;
  const BatchImportDialog({super.key, required this.bookId});

  @override
  ConsumerState<BatchImportDialog> createState() => _BatchImportDialogState();
}

class _BatchImportDialogState extends ConsumerState<BatchImportDialog> {
  final TextEditingController _folderController = TextEditingController();
  List<_ChapterFile> _files = [];
  final Set<int> _selectedIndexes = {};
  bool _scanning = false;
  bool _importing = false;
  String? _error;
  String? _scanMessage;

  @override
  void dispose() {
    _folderController.dispose();
    super.dispose();
  }

  /// 客户端备用扫描 (当后端不可用时)
  Future<void> _scanLocal() async {
    final folder = _folderController.text.trim();
    if (folder.isEmpty) {
      setState(() => _error = '请填写文件夹路径');
      return;
    }
    final dir = Directory(folder);
    if (!await dir.exists()) {
      setState(() => _error = '文件夹不存在: $folder');
      return;
    }
    setState(() {
      _scanning = true;
      _error = null;
      _scanMessage = null;
      _files = [];
      _selectedIndexes.clear();
    });
    try {
      final entries = await dir.list().toList();
      final files = <_ChapterFile>[];
      for (final e in entries) {
        if (e is! File) continue;
        final path = e.path;
        final ext = path.toLowerCase();
        if (!(ext.endsWith('.txt') || ext.endsWith('.md'))) continue;
        final stat = await e.stat();
        final content = await e.readAsString();
        final title = _extractTitle(path, content);
        files.add(_ChapterFile(
          path: path,
          name: path.split(Platform.pathSeparator).last,
          title: title,
          size: stat.size,
          preview: content.length > 200 ? content.substring(0, 200) : content,
        ));
      }
      files.sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _files = files;
        _selectedIndexes.addAll(List.generate(files.length, (i) => i));
        _scanMessage = files.isEmpty
            ? '未在文件夹中发现 .txt / .md 文件'
            : '发现 ${files.length} 个候选文件 (本地扫描)';
        _scanning = false;
      });
    } catch (e) {
      setState(() {
        _error = '本地扫描失败: $e';
        _scanning = false;
      });
    }
  }

  String _extractTitle(String path, String content) {
    final fileName = path.split(Platform.pathSeparator).last;
    final name = fileName.replaceAll(RegExp(r'\.(txt|md)$'), '');
    // 优先取 markdown 一级标题
    for (final line in content.split('\n').take(10)) {
      final t = line.trim();
      if (t.startsWith('# ')) {
        return t.substring(2).trim();
      }
    }
    return name;
  }

  Future<void> _import() async {
    if (_selectedIndexes.isEmpty) {
      setState(() => _error = '请至少选择一个文件');
      return;
    }
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final selected = _selectedIndexes.map((i) => _files[i]).toList();
      // 完全本地化导入: 直接走文件系统, 零 HTTP 依赖
      // .txt → 加 # 标题头转 markdown; .md → 原样复制
      // 已存在的章节跳过 (不覆盖用户已有内容)
      final files = selected
          .map((f) => (path: f.path, title: f.title))
          .toList();
      final result = await localDataSource.importChaptersFromFiles(
        widget.bookId,
        files,
      );
      ref.invalidate(booksProvider);
      if (mounted) {
        Navigator.of(context).pop({
          'created': result.success,
          'skipped': result.skipped,
          'method': 'local',
        });
      }
    } catch (e) {
      setState(() {
        _error = '导入失败: $e';
        _importing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.create_new_folder_outlined, size: 20),
          SizedBox(width: 8),
          Text('批量导入章节'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: SizedBox(
          width: 720,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择一个文件夹，自动扫描其中的 .txt / .md 文件批量创建为章节。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _folderController,
                      decoration: InputDecoration(
                        labelText: '文件夹路径',
                        hintText: '例如: D:\\novels\\chapters',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _scanning ? null : _scanLocal,
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text('扫描'),
                  ),
                ],
              ),
              if (_scanning) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_scanMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _scanMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ],
              if (_files.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '已选 ${_selectedIndexes.length} / ${_files.length}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedIndexes.clear();
                          _selectedIndexes.addAll(
                            List.generate(_files.length, (i) => i),
                          );
                        });
                      },
                      child: const Text('全选', style: TextStyle(fontSize: 11)),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _selectedIndexes.clear());
                      },
                      child: const Text('清空', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _files.length,
                      itemBuilder: (context, i) {
                        final f = _files[i];
                        final selected = _selectedIndexes.contains(i);
                        return InkWell(
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _selectedIndexes.remove(i);
                              } else {
                                _selectedIndexes.add(i);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.3)
                                  : null,
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: selected,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedIndexes.add(i);
                                      } else {
                                        _selectedIndexes.remove(i);
                                      }
                                    });
                                  },
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        f.title,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${f.name} · ${_formatSize(f.size)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context).disabledColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _importing || _selectedIndexes.isEmpty ? null : _import,
          icon: _importing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download, size: 14),
          label: Text(_importing ? '导入中…' : '导入 ${_selectedIndexes.length} 个'),
        ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _ChapterFile {
  final String path;
  final String name;
  final String title;
  final int size;
  final String preview;

  _ChapterFile({
    required this.path,
    required this.name,
    required this.title,
    required this.size,
    this.preview = '',
  });

  // ignore: unused_element
  factory _ChapterFile.fromJson(Map<String, dynamic> json) {
    return _ChapterFile(
      path: json['path'] ?? '',
      name: json['name'] ?? '',
      title: json['title'] ?? json['name'] ?? '',
      size: json['size'] ?? 0,
      preview: json['preview'] ?? '',
    );
  }
}
