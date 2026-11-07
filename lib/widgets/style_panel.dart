import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/api_routes.dart';

class StylePanel extends StatefulWidget {
  const StylePanel({super.key, this.profileLoader});

  final Future<ApiResponse> Function()? profileLoader;

  @override
  State<StylePanel> createState() => _StylePanelState();
}

class _StylePanelState extends State<StylePanel> {
  bool _loading = false;
  Map<String, dynamic>? _data;
  String? _error;

  Future<ApiResponse> _defaultLoad() => apiClient.get(ApiRoutes.styleProfile);

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await (widget.profileLoader ?? _defaultLoad)();
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (res.ok && res.data != null) {
          _data = res.data;
        } else {
          _data = null;
          _error = res.message.isNotEmpty ? res.message : '服务返回异常';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _data = null;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '文风画像',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _refresh,
                  icon:
                      _loading
                          ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新画像'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child:
                  _loading && _data == null && _error == null
                      ? const Center(child: Text('正在加载…'))
                      : _buildBody(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_error != null) {
      return ListView(children: [_offlineCard(theme)]);
    }
    if (_data == null) {
      return Center(
        child: Text(
          '点击刷新查看已定档画像与历史参考',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    return ListView(children: _buildContent(theme));
  }

  Widget _offlineCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '服务未连接，启动本机学习服务后可刷新',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              _error ?? '',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContent(ThemeData theme) {
    final widgets = <Widget>[];
    final meta = _asMap(_data!['meta']);
    final sampleCount = _asInt(meta['sample_count']);
    widgets.addAll(_buildPersonal(theme, sampleCount));
    widgets.addAll(_buildReference(theme));
    return widgets;
  }

  List<Widget> _buildPersonal(ThemeData theme, int sampleCount) {
    final widgets = <Widget>[
      Text(
        '我的写作画像',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 4),
    ];
    if (sampleCount <= 0) {
      widgets.addAll([
        Text(
          '尚无定档样本，完成章节定档后积累个人画像。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 12),
      ]);
      return widgets;
    }
    widgets.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          '已积累 $sampleCount 份定档样本',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.primaryColor),
        ),
      ),
    );
    final dims = _asMap(_data!['dimensions']);
    widgets.addAll(
      _dimensionTiles(theme, dims, isLegacy: false, showSamples: false),
    );
    widgets.add(const SizedBox(height: 12));
    return widgets;
  }

  List<Widget> _buildReference(ThemeData theme) {
    final training = _asMap(_data!['training']);
    final ref = _asMap(training['style_reference']);
    if (ref['available'] != true) {
      return [];
    }
    final total = _asInt(ref['sample_count']);
    final widgets = <Widget>[
      Text(
        '历史文风参考',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '总计 $total 份参考样本',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.primaryColor),
      ),
      const SizedBox(height: 4),
      Text(
        '参考样本按提取算法分别统计，不计入个人画像；这些指标不代表文笔评分。',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      const SizedBox(height: 8),
    ];
    final schemas = ref['schemas'];
    if (schemas is List) {
      for (final s in schemas) {
        final schema = _asMap(s);
        widgets.add(_schemaCard(theme, schema));
        widgets.add(const SizedBox(height: 8));
      }
    }
    widgets.addAll(_sourceLine(theme, ref['sources']));
    return widgets;
  }

  Widget _schemaCard(ThemeData theme, Map<String, dynamic> schema) {
    final schemaName = schema['schema']?.toString() ?? '';
    final isLegacy = schemaName == 'legacy_style_features';
    final count = _asInt(schema['sample_count']);
    final dims = _asMap(schema['dimensions']);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  schema['label']?.toString() ?? '参考特征',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '样本 $count 份',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ..._dimensionTiles(
              theme,
              dims,
              isLegacy: isLegacy,
              showSamples: true,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _sourceLine(ThemeData theme, dynamic sources) {
    if (sources is! List || sources.isEmpty) return [];
    final labels = <String>[];
    for (final s in sources) {
      final src = _asMap(s);
      final label = _sourceLabel(src['label']?.toString());
      final n = _asInt(src['sample_count']);
      labels.add('$label $n 份');
    }
    return [
      Text(
        '来源：${labels.join('、')}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    ];
  }

  String _sourceLabel(String? raw) {
    switch (raw) {
      case 'legacy-cdm':
        return '旧引擎目录';
      case 'private-data':
        return '私有特征目录';
      case 'private-cdm':
        return '私有训练目录';
      default:
        return '指定目录';
    }
  }

  List<Widget> _dimensionTiles(
    ThemeData theme,
    Map<String, dynamic> dims, {
    required bool isLegacy,
    required bool showSamples,
  }) {
    final tiles = <Widget>[];
    dims.forEach((key, raw) {
      final dim = _asMap(raw);
      final formatted = _formatDimension(key, dim, isLegacy: isLegacy);
      if (formatted == null) return;
      final samples = _asInt(dim['samples']);
      tiles.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(formatted, style: theme.textTheme.bodySmall),
              if (showSamples && samples > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '每项样本数 $samples',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
    return tiles;
  }

  String? _formatDimension(
    String key,
    Map<String, dynamic> dim, {
    required bool isLegacy,
  }) {
    final label = _dimLabel(key, isLegacy: isLegacy);
    if (label == null) return null;
    final v = dim['value'];
    if (v is! num || !v.isFinite || v < 0) return null;
    switch (key) {
      case 'avg_sentence_length':
        return '平均句长 ${v.toStringAsFixed(1)} 字/句';
      case 'paragraph_length_avg':
        return '平均段长 ${v.toStringAsFixed(1)} 字/段';
      case 'sentences_per_paragraph':
        return '每段句数 ${v.toStringAsFixed(1)} 句/段';
      case 'dialogue_ratio':
      case 'type_token_ratio':
      case 'sentence_short_pct':
      case 'sentence_medium_pct':
      case 'sentence_long_pct':
        if (v > 1) return null;
        return '$label ${_pct(v)}';
      case 'comma_per_100':
      case 'dash_per_100':
      case 'ellipsis_per_100':
        return '$label ${v.toStringAsFixed(1)} 次/百字';
      case 'metaphor_count':
      case 'parallelism_count':
      case 'rhetorical_q_count':
        return '$label ${v.toStringAsFixed(1)} 次/样本';
      default:
        return null;
    }
  }

  String _pct(num v) => '${(v * 100).toStringAsFixed(1)}%';

  String? _dimLabel(String key, {required bool isLegacy}) {
    switch (key) {
      case 'avg_sentence_length':
        return '平均句长';
      case 'paragraph_length_avg':
        return '平均段长';
      case 'sentences_per_paragraph':
        return '每段句数';
      case 'dialogue_ratio':
        return isLegacy ? '对话句占比' : '对话字数占比';
      case 'sentence_short_pct':
        return '短句占比';
      case 'sentence_medium_pct':
        return '中句占比';
      case 'sentence_long_pct':
        return '长句占比';
      case 'type_token_ratio':
        return '词汇丰富度';
      case 'comma_per_100':
        return '逗号密度';
      case 'dash_per_100':
        return '破折号密度';
      case 'ellipsis_per_100':
        return '省略号密度';
      case 'metaphor_count':
        return '比喻标记';
      case 'parallelism_count':
        return '排比标记';
      case 'rhetorical_q_count':
        return '反问标记';
      default:
        return null;
    }
  }

  Map<String, dynamic> _asMap(dynamic v) =>
      v is Map
          ? v.map((k, e) => MapEntry(k.toString(), e))
          : <String, dynamic>{};

  int _asInt(dynamic v) {
    if (v is num && v.isFinite && v >= 0) return v.toInt();
    return 0;
  }
}
