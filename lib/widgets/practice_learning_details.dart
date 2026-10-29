import 'package:flutter/material.dart';

import '../services/practice_learning_view.dart';

class PracticeLearningDetails extends StatefulWidget {
  final String root;
  final String book;
  final String caseId;
  final int? preferenceVersion;
  final bool Function() isCurrent;
  final Future<PracticeLearningView> Function(String, String, String) loadView;

  const PracticeLearningDetails({
    super.key,
    required this.root,
    required this.book,
    required this.caseId,
    required this.preferenceVersion,
    required this.isCurrent,
    this.loadView = PracticeLearningView.load,
  });

  @override
  State<PracticeLearningDetails> createState() => _LearningDetailsState();
}

class _LearningDetailsState extends State<PracticeLearningDetails> {
  PracticeLearningView? _view;
  String? _error;
  bool _expanded = false;
  bool _loading = false;
  int _generation = 0;

  @override
  void didUpdateWidget(covariant PracticeLearningDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.root != widget.root ||
        oldWidget.book != widget.book ||
        oldWidget.caseId != widget.caseId ||
        oldWidget.preferenceVersion != widget.preferenceVersion ||
        oldWidget.loadView != widget.loadView) {
      _generation++;
      _view = null;
      _error = null;
      _loading = false;
      if (_expanded) _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _view = null;
      _error = null;
      _loading = true;
    });
    try {
      if (!widget.isCurrent()) throw StateError('工作区或作品已切换，请重新打开。');
      final view = await widget.loadView(
        widget.root,
        widget.book,
        widget.caseId,
      );
      if (!mounted || generation != _generation) return;
      if (!widget.isCurrent()) throw StateError('工作区或作品已切换，请重新打开。');
      setState(() => _view = view);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = '本次复盘未能核对：$error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('这次练笔留下了什么'),
    subtitle: const Text('本机复盘 · 展开时核对当前偏好'),
    onExpansionChanged: (expanded) {
      _expanded = expanded;
      if (expanded) _load();
    },
    children: [
      if (_loading) const LinearProgressIndicator(),
      if (_error case final error?) SelectableText(error),
      if (_view case final view?) ...[
        _section(
          '你的选择',
          {
            'pending': '当时尚未决定',
            'try': '当时选择尝试，尚不代表确认长期偏好',
            'reject': '当时认为建议不适合，模型方向仍只保留为历史意见',
            'defer': '当时暂缓处理，尚不代表确认长期偏好',
          }[view.record.decision]!,
        ),
        _section(
          '自改与效果',
          '${view.record.revision.isEmpty ? "未保存自改" : "已保存自改"}；${view.record.revisionFeedback == null ? "未保存复评" : "已保存模型复评"}。尚不能据此判断文笔提升。',
        ),
        _section(
          '从这次练笔明确确认的偏好',
          view.confirmed.isEmpty
              ? '当前没有生效项。模型建议与尝试决定不会自动成为规则。'
              : view.confirmed.map((item) => item.text).join('\n'),
        ),
        if (view.revoked.isNotEmpty)
          _section(
            '已撤销，仅供回看',
            view.revoked.map((item) => item.text).join('\n'),
          ),
        _section('模型提供的可试方向', '共 ${view.candidates.length} 条，仍为候选；是否适合由你判断。'),
        for (final candidate in view.candidates)
          _section(
            '${candidate.fromRevision ? "改稿" : "原稿"}反馈 · ${candidate.hasStoredSource ? "已保存调用关联，原记录待核对" : "未记录调用关联"}',
            '“${candidate.observation.quote}”\n${candidate.observation.direction}',
          ),
        Text('偏好版本 ${view.preferenceVersion} · 读取时的状态；没有训练或发送正文。'),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _loading ? null : _load,
          child: const Text('重新核对复盘'),
        ),
      ),
    ],
  );

  Widget _section(String title, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          SelectableText(text),
        ],
      ),
    ),
  );
}
