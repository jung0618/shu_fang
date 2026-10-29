import 'package:flutter/material.dart';

import '../services/writing_goal.dart';

/// Book-scoped explicit goals, independently saved from a practice case.
class WritingGoalPanel extends StatefulWidget {
  final String root;
  final String book;
  final bool locked;
  final bool Function() isCurrent;
  final void Function(AuthorWritingGoal? goal, bool ready, bool dirty)
  onChanged;

  const WritingGoalPanel({
    super.key,
    required this.root,
    required this.book,
    required this.locked,
    required this.isCurrent,
    required this.onChanged,
  });

  @override
  State<WritingGoalPanel> createState() => _WritingGoalPanelState();
}

class _WritingGoalPanelState extends State<WritingGoalPanel> {
  final _target = TextEditingController();
  final _keep = TextEditingController();
  final _avoid = TextEditingController();
  AuthorWritingGoal? _goal;
  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _restoreFields() {
    _target.text = _goal?.target ?? '';
    _keep.text = _goal?.keep ?? '';
    _avoid.text = _goal?.avoid ?? '';
  }

  Future<void> _load() async {
    try {
      final goal = await WritingGoalStore.load(
        root: widget.root,
        book: widget.book,
      );
      if (!mounted) return;
      if (!widget.isCurrent()) throw StateError('工作区或章节已切换，请重新打开练笔');
      setState(() {
        _goal = goal;
        _loading = false;
        _error = null;
        _editing = false;
        _restoreFields();
      });
      widget.onChanged(goal, true, false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
      widget.onChanged(_goal, false, _editing);
    }
  }

  Future<void> _save({bool enabled = true}) async {
    if (_saving || widget.locked) return;
    if (!widget.isCurrent()) {
      setState(() => _error = '工作区或章节已切换，请重新打开练笔');
      widget.onChanged(_goal, false, _editing);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    widget.onChanged(_goal, false, _editing);
    try {
      final goal = await WritingGoalStore.save(
        root: widget.root,
        book: widget.book,
        expectedVersion: _goal?.version,
        target: _target.text,
        keep: _keep.text,
        avoid: _avoid.text,
        enabled: enabled,
      );
      if (!mounted) return;
      if (!widget.isCurrent()) throw StateError('目标已保存到原作品，请重新打开练笔');
      setState(() {
        _goal = goal;
        _editing = false;
        _restoreFields();
      });
      widget.onChanged(goal, true, false);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '作品目标未能完成更新：$error');
        widget.onChanged(_goal, false, _editing);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _target.dispose();
    _keep.dispose();
    _avoid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.locked || _saving || _loading;
    final goal = _goal;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('这部作品想写成什么样', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            if (_loading)
              const LinearProgressIndicator()
            else if (_editing) ...[
              const Text('按你的方向给建议，也保留你不想改掉的部分。目标只用于当前作品。'),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('writing-goal-target'),
                controller: _target,
                enabled: !locked,
                maxLength: 400,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '想接近的方向',
                  hintText: '例如：对白克制，情绪藏在动作里，读起来仍然轻快。',
                ),
              ),
              TextField(
                key: const ValueKey('writing-goal-keep'),
                controller: _keep,
                enabled: !locked,
                maxLength: 300,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '想保留什么（可选）'),
              ),
              TextField(
                key: const ValueKey('writing-goal-avoid'),
                controller: _avoid,
                enabled: !locked,
                maxLength: 300,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '想避免什么（可选）'),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: locked ? null : () => _save(),
                    child: Text(_saving ? '保存中…' : '保存作品目标'),
                  ),
                  TextButton(
                    onPressed:
                        locked
                            ? null
                            : () {
                              setState(() {
                                _editing = false;
                                _error = null;
                                _restoreFields();
                              });
                              widget.onChanged(_goal, true, false);
                            },
                    child: const Text('取消编辑'),
                  ),
                ],
              ),
            ] else ...[
              Text(
                goal == null
                    ? '尚未设置作品目标，可以先做一次选段练习。'
                    : goal.enabled
                    ? '本次沿用第 ${goal.version} 版作品目标'
                    : '作品目标已停用，本次按选段练习目标反馈。',
              ),
              if (goal != null && goal.enabled) ...[
                const SizedBox(height: 8),
                Text(goal.target),
                if (goal.keep.isNotEmpty) Text('保留：${goal.keep}'),
                if (goal.avoid.isNotEmpty) Text('避免：${goal.avoid}'),
              ],
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed:
                        locked || _error != null
                            ? null
                            : () {
                              setState(() => _editing = true);
                              widget.onChanged(_goal, false, true);
                            },
                    child: Text(goal == null ? '设置作品目标' : '编辑作品目标'),
                  ),
                  if (goal != null)
                    TextButton(
                      onPressed:
                          locked || _error != null
                              ? null
                              : () => _save(enabled: !goal.enabled),
                      child: Text(goal.enabled ? '停用目标' : '重新启用'),
                    ),
                ],
              ),
            ],
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed:
                    locked
                        ? null
                        : () {
                          setState(() => _loading = true);
                          widget.onChanged(_goal, false, _editing);
                          _load();
                        },
                child: const Text('重新载入目标'),
              ),
            ],
            if (widget.locked) const Text('本次目标已固定；下次练笔可编辑作品目标。'),
          ],
        ),
      ),
    );
  }
}
