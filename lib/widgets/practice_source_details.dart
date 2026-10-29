import 'package:flutter/material.dart';

import '../services/writing_practice.dart';
import '../services/writing_request_ledger.dart';

/// On-demand, read-only checking keeps technical details out of the writing flow.
class PracticeSourceDetails extends StatefulWidget {
  final String title;
  final String root;
  final PracticeFeedbackSource? source;
  final bool Function() isCurrent;
  const PracticeSourceDetails({
    super.key,
    required this.title,
    required this.root,
    required this.source,
    required this.isCurrent,
  });

  @override
  State<PracticeSourceDetails> createState() => _PracticeSourceDetailsState();
}

class _PracticeSourceDetailsState extends State<PracticeSourceDetails> {
  bool _checking = false;
  String? _result;

  @override
  void didUpdateWidget(PracticeSourceDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.root != widget.root || oldWidget.source != widget.source) {
      _checking = false;
      _result = null;
    }
  }

  Future<void> _check() async {
    final source = widget.source;
    final root = widget.root;
    if (_checking || source == null || !widget.isCurrent()) return;
    setState(() {
      _checking = true;
      _result = null;
    });
    String result;
    try {
      final page = await WritingRequestLedger.read(
        root,
        requestId: source.request.requestId,
      );
      if (page.problems.isNotEmpty) {
        result = '调用记录无法完整读取，原文件保留。';
      } else if (page.records.isEmpty) {
        result = '未找到本地调用记录；保留来源快照，不推断执行结果。';
      } else if (source.request.matchesRecord(page.records.single)) {
        result = '与本地完成记录一致。这不代表建议已获作者认可或费用已结清。';
      } else {
        result = '来源与本地调用记录不一致，请保留原文件核查。';
      }
    } catch (_) {
      result = '暂时无法核对，原记录未改动。';
    }
    if (!mounted || widget.root != root || widget.source != source) return;
    setState(() {
      _checking = false;
      _result = widget.isCurrent() ? result : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    return ExpansionTile(
      title: Text(widget.title),
      subtitle: Text(source == null ? '来源未记录' : '已保存来源快照，展开核对'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children:
          source == null
              ? const [Text('这份反馈没有保存调用关联，不按时间或模型名猜测来源。')]
              : [
                Text(
                  '请求模型：${source.request.model} · ${source.request.route == 'engine' ? '写作引擎' : '直接连接'}',
                ),
                SelectableText('调用编号：${source.request.requestId}'),
                SelectableText('输入指纹：${source.request.contextSha256}'),
                SelectableText('原始回复指纹：${source.request.outputSha256}'),
                const Text('指纹用于核对关联，不是防篡改签名或文笔评定。'),
                TextButton(
                  onPressed: _checking || !widget.isCurrent() ? null : _check,
                  child: Text(_checking ? '正在核对…' : '核对本地调用'),
                ),
                if (_result != null) Text(_result!),
              ],
    );
  }
}
