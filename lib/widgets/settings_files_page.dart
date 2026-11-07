import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_routes.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';
import 'setting_file_edit_dialog.dart';

/// 设定/标签文件扫描面板
class SettingsFilesPage extends ConsumerStatefulWidget {
  const SettingsFilesPage({super.key});

  @override
  ConsumerState<SettingsFilesPage> createState() => _SettingsFilesPageState();
}

class _SettingsFilesPageState extends ConsumerState<SettingsFilesPage> {
  bool _busy = false;
  // 引擎可达性 (初始化时探测一次, 决定"重建索引"按钮是否可用)
  bool? _engineReady;

  @override
  void initState() {
    super.initState();
    _checkEngine();
  }

  Future<void> _checkEngine() async {
    final ok = await LocalDataSource.isEngineReachable();
    if (mounted) setState(() => _engineReady = ok);
  }

  Future<void> _scan() async {
    setState(() => _busy = true);
    // 本地扫描: 直接 invalidate provider, 让 listSettingFiles() 重跑
    // 零 HTTP 依赖, 引擎不启动也能用
    try {
      ref.invalidate(settingsFilesProvider);
      ref.invalidate(unitSettingsProvider);
      final files = await ref.read(settingsFilesProvider.future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描完成: ${files.length} 个设定文件')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('扫描失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reindex() async {
    // 引擎不可达时直接拒绝 (按钮已禁用, 此为兜底)
    if (_engineReady != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('引擎未启动, 无法重建索引。请先启动 ShuFang 全局启动器')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await apiClient.post(ApiRoutes.loreBuild, body: {'type': 'full'});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.data?['status'] == 'started'
              ? '索引重建已启动 (build_id: ${res.data?['build_id']})'
              : '已触发重建')),
        );
        ref.invalidate(loreBuildStatusProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重建失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // D37 Phase 2-2 (P0-10): 新建设定文件
  Future<void> _createFile() async {
    final books = await localDataSource.listBooks();
    if (!mounted) return;
    if (books.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建至少一本书籍')),
      );
      return;
    }
    String? selectedBookId = books.first.id;
    final controller = TextEditingController();
    final result = await showDialog<({String bookId, String fileName})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('新建设定文件'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedBookId,
                    decoration: const InputDecoration(labelText: '所属书籍'),
                    items: books
                        .map((b) => DropdownMenuItem(
                              value: b.id,
                              child: Text(b.name),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => selectedBookId = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: '文件名 (例如: 反派设定.md)',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      final name = v.trim();
                      if (name.isNotEmpty) {
                        Navigator.pop(ctx,
                            (bookId: selectedBookId, fileName: name));
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = controller.text.trim();
                    if (name.isNotEmpty) {
                      Navigator.pop(ctx,
                          (bookId: selectedBookId, fileName: name));
                    }
                  },
                  child: const Text('创建'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null) return;
    final ok = await localDataSource.createSettingFile(
        result.bookId, result.fileName);
    if (ok) {
      ref.invalidate(settingsFilesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已创建, 点击文件可编辑'), duration: Duration(seconds: 1)),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建失败: 文件可能已存在')),
      );
    }
  }

  // D37 Phase 2-5 (P1-8): 删除设定文件
  Future<void> _deleteFile(SettingFile f) async {
    // f.path 格式: "<bookId>/settings/<filename>"
    final parts = f.path.split('/');
    if (parts.length < 3) return;
    final bookId = parts[0];
    final fileName = parts.last;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除设定文件'),
        content: Text('确定要删除 "$fileName" 吗? 此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await localDataSource.deleteSettingFile(bookId, fileName);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(deleted ? '已删除' : '删除失败')),
      );
      if (deleted) ref.invalidate(settingsFilesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filesAsync = ref.watch(settingsFilesProvider);
    final statusAsync = ref.watch(loreBuildStatusProvider);
    final engineBlocked = _engineReady == false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('设定 / 标签'),
        actions: [
          // D37 Phase 2-2 (P0-10): 新建设定文件按钮
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建设定文件',
            onPressed: _busy ? null : _createFile,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新扫描 (本地)',
            onPressed: _busy ? null : _scan,
          ),
          // 引擎不可达时禁用, 并提示原因
          IconButton(
            icon: Icon(
              Icons.replay_circle_filled_outlined,
              color: engineBlocked ? Theme.of(context).disabledColor : null,
            ),
            tooltip: engineBlocked
                ? '引擎未启动, 无法重建索引'
                : '重建索引 (需引擎)',
            onPressed: (_busy || engineBlocked) ? null : _reindex,
          ),
        ],
      ),
      body: Column(
        children: [
          // 引擎状态提示条 (不可达时显示)
          if (engineBlocked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 14,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '引擎未启动 — 扫描可用, 重建索引/单元集等高级功能需启动 ShuFang 全局启动器',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          // 状态卡
          statusAsync.when(
            data: (status) {
              if (status.isEmpty) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in status.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 100,
                              child: Text('${entry.key}:',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ),
                            Expanded(
                              child: Text('${entry.value}',
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: filesAsync.when(
              data: (files) {
                if (files.isEmpty) {
                  return const Center(child: Text('未发现设定文件，请先创建'));
                }
                return ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = files[i];
                    // D37 Phase 2-2 (P0-10): ListTile 加 onTap 打开编辑对话框
                    // f.path 格式: "<bookId>/settings/<filename>"
                    final parts = f.path.split('/');
                    final bookId = parts.isNotEmpty ? parts[0] : '';
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.description_outlined, size: 18),
                      title: Text(f.name, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        f.path,
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            f.size > 1024
                                ? '${(f.size / 1024).toStringAsFixed(1)} KB'
                                : '${f.size} B',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          // D37 Phase 2-5 (P1-8): 删除按钮
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16),
                            tooltip: '删除',
                            onPressed: () => _deleteFile(f),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      onTap: () async {
                        // 真正读文件内容 → 弹编辑对话框 → 保存
                        await showSettingFileEditDialog(context, bookId, f.name);
                        if (context.mounted) {
                          // 保存后刷新 (文件大小/修改时间可能变化)
                          ref.invalidate(settingsFilesProvider);
                        }
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
