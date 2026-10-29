import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/writing_request_ledger.dart';
import '../store/local_data_source.dart';

/// Read-only evidence. There is deliberately no replay button: a missing reply
/// or unknown bill must never silently trigger a second paid generation.
class WritingRequestHistoryDialog extends StatefulWidget {
  final String root;
  const WritingRequestHistoryDialog({super.key, required this.root});

  @override
  State<WritingRequestHistoryDialog> createState() => _HistoryState();
}

class _HistoryState extends State<WritingRequestHistoryDialog> {
  final _records = <WritingRequestRecord>[];
  final _problems = <String>[];
  String? _cursor;
  String? _error;
  bool _loading = true;
  late final int _revision;

  @override
  void initState() {
    super.initState();
    _revision = localDataSource.sessionRevision;
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await WritingRequestLedger.read(
        widget.root,
        cursor: more ? _cursor : null,
      );
      if (!mounted) return;
      if (_revision != localDataSource.sessionRevision ||
          widget.root != localDataSource.storageRoot) {
        setState(() {
          _records.clear();
          _problems.clear();
          _cursor = null;
          _error = '工作区已切换，请关闭后重新查看。';
        });
        return;
      }
      setState(() {
        if (!more) {
          _records.clear();
          _problems.clear();
        }
        _records.addAll(page.records);
        _problems.addAll(page.problems);
        _cursor = page.nextCursor;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '暂时无法读取记录，原文件保留。请检查工作区是否可访问。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 760,
        height: size.height * .82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('写作调用记录', style: theme.textTheme.headlineMedium),
                        const SizedBox(height: 8),
                        Text(
                          '每次生成，留一份清楚的来路。',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新记录',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child:
                  _loading && _records.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Text(
                            '讨论 · 快捷操作 · 选段练笔',
                            style: theme.textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '只记录当前工作区。用量来自服务返回；费用未核对时保持未知。',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 24),
                          if (_error != null) _Notice(_error!),
                          if (_problems.isNotEmpty)
                            _Notice(_problems.join('\n')),
                          if (_records.isEmpty &&
                              _error == null &&
                              _problems.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.receipt_long_outlined,
                                    size: 32,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '还没有写作调用',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '下一次讨论或练笔后，可以在这里查看请求状态。',
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          for (final record in _records) _RequestRow(record),
                          if (_cursor != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: OutlinedButton(
                                onPressed:
                                    _loading ? null : () => _load(more: true),
                                child: const Text('查看更早记录'),
                              ),
                            ),
                          if (_loading) const LinearProgressIndicator(),
                          const SizedBox(height: 24),
                          Text(
                            '中断本地接收不代表服务端已取消。缺少完成回执的请求不会自动重试；记录不保存原稿、回复正文或密钥。',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

class _RequestRow extends StatelessWidget {
  final WritingRequestRecord record;
  const _RequestRow(this.record);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = record.meta;
    final result = record.result;
    final time = DateTime.parse(record.createdAt).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${time.year}.${two(time.month)}.${two(time.day)}  ${two(time.hour)}:${two(time.minute)}';
    final usage = result['usage'];
    final counts =
        usage is Map
            ? [
              if (usage['prompt_tokens'] is int) '输入 ${usage['prompt_tokens']}',
              if (usage['completion_tokens'] is int)
                '输出 ${usage['completion_tokens']}',
              if (usage['total_tokens'] is int) '合计 ${usage['total_tokens']}',
            ]
            : <String>[];
    final title = [
      meta['book'],
      meta['chapter'],
    ].where((v) => v is String && v.isNotEmpty).join(' / ');
    final task = switch (meta['task']) {
      'feedback' => '表达反馈',
      'revision' => '改写',
      'continuation' => '续写',
      'summary' => '概括',
      _ => '写作讨论',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        iconColor: theme.colorScheme.onSurfaceVariant,
        collapsedIconColor: theme.colorScheme.onSurfaceVariant,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          title.isEmpty ? task : title,
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$task · $stamp', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(record.statusLabel, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                '${counts.isEmpty ? '用量未知' : '${counts.join(' · ')} token'} · 费用未知',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(),
                SelectableText(
                  '请求模型：${meta['requested_model']}\n服务报告模型：${result['observed_model'] ?? '未提供'}\n通道：${meta['route'] == 'engine' ? '本机引擎' : '已配置的直连服务'}\n参考范围：${meta['source_units']}/${meta['total_source_units']} 字符\n上下文预算：${meta['used_units']}/${meta['budget_units']} UTF-16 单位\n未发送的较早对话：${meta['omitted_turns']} 轮',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  '请求编号：${record.id}\n服务请求编号：${result['provider_request_id'] ?? '未提供'}\n输入摘要：${meta['context_sha256']}',
                  style: theme.textTheme.bodySmall,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                    ),
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('复制请求编号'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: record.id));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请求编号已复制')),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
