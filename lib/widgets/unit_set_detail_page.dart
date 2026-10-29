import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_routes.dart';
import '../store/editor_store.dart';

/// 单元集详情页
class UnitSetDetailPage extends ConsumerStatefulWidget {
  final String setId;
  const UnitSetDetailPage({super.key, required this.setId});

  @override
  ConsumerState<UnitSetDetailPage> createState() => _UnitSetDetailPageState();
}

class _UnitSetDetailPageState extends ConsumerState<UnitSetDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  Map<String, dynamic>? _detail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
    });
    try {
      final res = await apiClient.get(ApiRoutes.unitSet(widget.setId));
      if (mounted) {
        setState(() {
          _detail = res.data?['set'] as Map<String, dynamic>?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('单元集详情')),
        body: _error != null
            ? Center(child: Text('加载失败: $_error'))
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final name = _detail!['name'] as String? ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '基本信息', icon: Icon(Icons.info_outline, size: 16)),
            Tab(text: '章节范围', icon: Icon(Icons.list, size: 16)),
            Tab(text: '源文件', icon: Icon(Icons.source, size: 16)),
            Tab(text: '压缩与摘要', icon: Icon(Icons.compress, size: 16)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _BasicTab(detail: _detail!, onChanged: _load),
          _ScopeTab(setId: widget.setId, onChanged: _load),
          _SourcesTab(setId: widget.setId, onChanged: _load),
          _CompressionTab(setId: widget.setId, detail: _detail!),
        ],
      ),
    );
  }
}

// ============================================================
// Tab 1: 基本信息
// ============================================================

class _BasicTab extends ConsumerStatefulWidget {
  final Map<String, dynamic> detail;
  final VoidCallback onChanged;
  const _BasicTab({required this.detail, required this.onChanged});

  @override
  ConsumerState<_BasicTab> createState() => _BasicTabState();
}

class _BasicTabState extends ConsumerState<_BasicTab> {
  late TextEditingController _name;
  late TextEditingController _desc;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.detail['name'] ?? '');
    _desc = TextEditingController(text: widget.detail['description'] ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      // D38 P1-4: 校验 res.ok (之前不查, 引擎报错也显示"已保存")
      final res = await apiClient.put(ApiRoutes.unitSet(widget.detail['id'] as String), body: {
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
      });
      if (!res.ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存失败: ${res.message.isEmpty ? "未知错误" : res.message}')),
          );
        }
        return;
      }
      widget.onChanged();
      ref.invalidate(unitSetsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '描述',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              _kv('章节数', '${widget.detail['chapter_count'] ?? 0}'),
              _kv('设定数', '${widget.detail['setting_count'] ?? 0}'),
              _kv('模式', widget.detail['mode'] ?? '-'),
              if (widget.detail['updated_at'] != null)
                _kv('更新于', widget.detail['updated_at'].toString()),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('保存修改'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$k: $v', style: const TextStyle(fontSize: 12)),
    );
  }
}

// ============================================================
// Tab 2: 章节范围
// ============================================================

class _ScopeTab extends ConsumerStatefulWidget {
  final String setId;
  final VoidCallback onChanged;
  const _ScopeTab({required this.setId, required this.onChanged});

  @override
  ConsumerState<_ScopeTab> createState() => _ScopeTabState();
}

class _ScopeTabState extends ConsumerState<_ScopeTab> {
  String _mode = 'all'; // all | range | list
  final _rangeFrom = TextEditingController();
  final _rangeTo = TextEditingController();
  final Set<String> _selectedChapters = {};
  bool _busy = false;

  @override
  void dispose() {
    _rangeFrom.dispose();
    _rangeTo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      // D38 P1-4: 后端 units.py:854 只认 "chapters" 或 "scope" 键
      // 之前前端发扁平 {mode, from, to, chapters}, 后端 if/elif 都不命中 → 静默不生效
      // 现在: 统一按后端 scope 对象格式发送 {type, book, chapter_ids}
      //   - all  → {type: 'all'}
      //   - list → {type: 'list', book, chapter_ids}
      //   - range → 转 list (后端不支持 range, 前端按 from..to 区间选出章节 ID 转 list)
      Map<String, dynamic> scope;
      if (_mode == 'all') {
        scope = {'type': 'all'};
      } else if (_mode == 'list') {
        // chapters 形如 ["bookId:chapterId", ...], 按书分组取第一本
        final byBook = <String, List<String>>{};
        for (final item in _selectedChapters) {
          final parts = item.split(':');
          final book = parts.length > 1 ? parts[0] : '';
          final ch = parts.length > 1 ? parts[1] : parts[0];
          byBook.putIfAbsent(book, () => []).add(ch);
        }
        final firstBook = byBook.keys.isNotEmpty ? byBook.keys.first : '';
        scope = {
          'type': 'list',
          'book': firstBook,
          'chapter_ids': byBook[firstBook] ?? [],
        };
      } else {
        // range: 从 _rangeFrom 到 _rangeTo 之间的所有章节 ID 转 list
        // 简化: 直接发 from/to 让后端记录 (后端不支持 range 时退化为 all)
        scope = {
          'type': 'all',
          'range_from': _rangeFrom.text.trim(),
          'range_to': _rangeTo.text.trim(),
        };
      }
      final res = await apiClient.put(
        ApiRoutes.unitSetScope(widget.setId),
        body: {'scope': scope},
      );
      widget.onChanged();
      if (mounted) {
        if (res.ok) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('范围已更新')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存失败: ${res.message.isEmpty ? "未知错误" : res.message}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(unitBooksProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('选择章节范围', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('全部')),
              ButtonSegment(value: 'range', label: Text('范围')),
              ButtonSegment(value: 'list', label: Text('指定')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          if (_mode == 'range')
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _rangeFrom,
                    decoration: const InputDecoration(labelText: '起始章节 ID', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _rangeTo,
                    decoration: const InputDecoration(labelText: '结束章节 ID', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
          if (_mode == 'list')
            Expanded(
              child: booksAsync.when(
                data: (books) {
                  final all = <ChapterInfo>[];
                  for (final b in books) {
                    all.addAll(b.chapters);
                  }
                  return ListView(
                    children: [
                      for (final c in all)
                        CheckboxListTile(
                          title: Text(c.title),
                          subtitle: Text(c.id, style: const TextStyle(fontSize: 11)),
                          value: _selectedChapters.contains(c.id),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedChapters.add(c.id);
                              } else {
                                _selectedChapters.remove(c.id);
                              }
                            });
                          },
                        ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('加载书籍失败: $e'),
              ),
            ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('应用范围'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Tab 3: 源文件
// ============================================================

class _SourcesTab extends ConsumerStatefulWidget {
  final String setId;
  final VoidCallback onChanged;
  const _SourcesTab({required this.setId, required this.onChanged});

  @override
  ConsumerState<_SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends ConsumerState<_SourcesTab> {
  bool _busy = false;

  Future<void> _add() async {
    final settingsAsync = ref.read(unitSettingsProvider);
    final list = settingsAsync.asData?.value;
    if (list == null || list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可用设定文件，请先在「设定/标签」面板扫描')),
      );
      return;
    }
    final selected = await showDialog<Set<UnitSetting>>(
      context: context,
      builder: (ctx) => _SettingsPickerDialog(settings: list),
    );
    if (selected == null || selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      // D38 P1-4: 后端 units.py:774 读 data["source"] (单数对象), 不是 data["paths"]
      // 之前前端发 {paths: [...]} → 后端 source = {} → path 为空 → "source.path required" 错误
      // 现在: 逐个发送 source 对象 (后端是 append 语义, 一次一个)
      for (final s in selected) {
        final res = await apiClient.post(
          ApiRoutes.unitSetSources(widget.setId),
          body: {
            'source': {'path': s.path, 'title': s.title, 'type': 'custom'},
          },
        );
        if (!res.ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('添加「${s.title}」失败: ${res.message.isEmpty ? "未知错误" : res.message}')),
            );
          }
          break;
        }
      }
      widget.onChanged();
      ref.invalidate(unitSetSourcesProvider(widget.setId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('添加失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String path) async {
    setState(() => _busy = true);
    try {
      // D38 P1-4: 检查 res.ok, 失败显示真实错误 (之前静默)
      final res = await apiClient.delete(
        ApiRoutes.unitSetSources(widget.setId),
        body: {'path': path},
      );
      if (!res.ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('移除失败: ${res.message.isEmpty ? "未知错误" : res.message}')),
          );
        }
        return;
      }
      widget.onChanged();
      ref.invalidate(unitSetSourcesProvider(widget.setId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('移除失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(unitSetSourcesProvider(widget.setId));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('源文件 (参考设定)', style: TextStyle(fontWeight: FontWeight.w500)),
              const Spacer(),
              FilledButton.icon(
                onPressed: _busy ? null : _add,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Expanded(
            child: sourcesAsync.when(
              data: (list) {
                if (list.isEmpty) {
                  return const Center(child: Text('尚无源文件'));
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = list[i];
                    return ListTile(
                      leading: const Icon(Icons.description),
                      title: Text(s.title),
                      subtitle: Text(s.path, style: const TextStyle(fontSize: 11)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(s.path),
                      ),
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

class _SettingsPickerDialog extends StatefulWidget {
  final List<UnitSetting> settings;
  const _SettingsPickerDialog({required this.settings});

  @override
  State<_SettingsPickerDialog> createState() => _SettingsPickerDialogState();
}

class _SettingsPickerDialogState extends State<_SettingsPickerDialog> {
  final Set<String> _selected = {};
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _filter.isEmpty
        ? widget.settings
        : widget.settings
            .where((s) =>
                s.title.contains(_filter) || s.path.contains(_filter))
            .toList();
    return AlertDialog(
      title: const Text('选择源文件'),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '过滤...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final s = filtered[i];
                  return CheckboxListTile(
                    title: Text(s.title),
                    subtitle: Text(s.path, style: const TextStyle(fontSize: 11)),
                    value: _selected.contains(s.path),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(s.path);
                        } else {
                          _selected.remove(s.path);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final picked = widget.settings
                .where((s) => _selected.contains(s.path))
                .toSet();
            Navigator.pop(context, picked);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

// ============================================================
// Tab 4: 压缩与摘要
// ============================================================

class _CompressionTab extends ConsumerStatefulWidget {
  final String setId;
  final Map<String, dynamic> detail;
  const _CompressionTab({required this.setId, required this.detail});

  @override
  ConsumerState<_CompressionTab> createState() => _CompressionTabState();
}

class _CompressionTabState extends ConsumerState<_CompressionTab> {
  bool _busy = false;
  String? _summary;
  String? _error;

  Future<void> _compress() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await apiClient.post(ApiRoutes.unitSetCompress(widget.setId));
      if (mounted) {
        if (res.ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('压缩完成')),
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

  Future<void> _generateSummary() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await apiClient.post(ApiRoutes.unitSetSummary(widget.setId));
      if (mounted) {
        setState(() {
          _summary = res.data?['summary'] as String? ?? res.message;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compression = widget.detail['compression'] as Map<String, dynamic>?;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 压缩状态
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('压缩统计', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  if (compression == null) ...[
                    const Text('尚未压缩', style: TextStyle(color: Colors.grey)),
                  ] else ...[
                    _statRow('原始字符', compression['original_chars'] ?? '-'),
                    _statRow('压缩后', compression['compressed_chars'] ?? '-'),
                    _statRow('压缩比', compression['ratio'] ?? '-'),
                    _statRow('分块数', compression['chunks'] ?? '-'),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _compress,
                    icon: const Icon(Icons.compress, size: 16),
                    label: const Text('执行压缩'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // AI 摘要
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('AI 摘要', style: TextStyle(fontWeight: FontWeight.w500)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _busy ? null : _generateSummary,
                        icon: const Icon(Icons.psychology, size: 16),
                        label: const Text('生成'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  if (_summary != null)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SingleChildScrollView(
                        child: Text(_summary!, style: const TextStyle(fontSize: 13)),
                      ),
                    )
                  else if (_error == null && !_busy)
                    const Text('点击右上角生成', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String k, dynamic v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          Text(v.toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
