import 'package:flutter/material.dart';
import 'practice_source_details.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/editor_request_lease.dart';
import '../services/writing_practice.dart';
import '../services/writing_practice_history.dart';
import '../services/writing_preferences.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';

void showWritingPracticeHistory(BuildContext context, WidgetRef ref) {
  final book = ref.read(currentBookProvider);
  if (book == null) return;
  final root = localDataSource.storageRoot;
  final lease = EditorRequestLease(ref);
  showDialog<void>(
    context: context,
    builder:
        (_) => WritingPracticeHistoryDialog(
          root: root,
          book: book,
          isCurrent:
              () => lease.isCurrent && localDataSource.storageRoot == root,
        ),
  );
}

class WritingPracticeHistoryDialog extends StatefulWidget {
  final String root;
  final String book;
  final bool Function() isCurrent;
  const WritingPracticeHistoryDialog({
    super.key,
    required this.root,
    required this.book,
    required this.isCurrent,
  });
  @override
  State<WritingPracticeHistoryDialog> createState() => _HistoryState();
}

class _HistoryState extends State<WritingPracticeHistoryDialog> {
  final _records = <WritingPracticeCase>[];
  final _problems = <String>[];
  WritingPreferences? _preferences;
  WritingPracticeCase? _selected;
  String? _cursor;
  String? _error;
  String? _preferencesError;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _current() {
    if (widget.isCurrent()) return true;
    if (mounted) setState(() => _error = '工作区或作品已切换，请关闭后重新打开。');
    return false;
  }

  Future<void> _load({bool more = false}) async {
    if (!_current()) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!more) {
        try {
          final preferences = await WritingPreferenceStore.load(
            widget.root,
            widget.book,
          );
          if (!mounted || !_current()) return;
          setState(() {
            _preferences = preferences;
            _preferencesError = null;
          });
        } catch (error) {
          if (!mounted || !_current()) return;
          setState(() {
            _preferences = null;
            _preferencesError = '作品偏好未能载入：$error';
          });
        }
      }
      final page = await WritingPracticeHistory.loadPage(
        widget.root,
        widget.book,
        beforeId: more ? _cursor : null,
      );
      if (!mounted || !_current()) return;
      setState(() {
        if (!more) {
          _records.clear();
          _problems.clear();
          _selected = null;
        }
        _records.addAll(page.records);
        _problems.addAll(page.problems);
        _cursor = page.nextCursor;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '练习记录未能载入：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm(WritingPracticeCase record) async {
    final previous = _preferences;
    if (_saving || previous == null || !_current()) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _PreferenceConfirmation(book: widget.book),
    );
    if (!mounted || text == null || !_current()) return;
    await _write(
      () => WritingPreferenceStore.confirm(
        root: widget.root,
        book: widget.book,
        expectedVersion: previous.version,
        sourceCaseId: record.id,
        text: text,
      ),
    );
  }

  Future<void> _revoke(ConfirmedWritingPreference item) async {
    final previous = _preferences;
    if (_saving || previous == null || !_current()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('撤销这项作品偏好？'),
            content: Text('“${item.text}”将不再用于之后的新练笔。已经生成的反馈与练习记录仍保留当时的偏好快照。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('保留'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认撤销'),
              ),
            ],
          ),
    );
    if (!mounted || confirmed != true || !_current()) return;
    await _write(
      () => WritingPreferenceStore.revoke(
        root: widget.root,
        book: widget.book,
        expectedVersion: previous.version,
        id: item.id,
      ),
    );
  }

  Future<void> _write(Future<WritingPreferences> Function() operation) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await operation();
      if (!mounted || !_current()) return;
      setState(() => _preferences = result);
    } catch (error) {
      if (mounted) setState(() => _error = '$error；可重新载入后再操作。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _source(String id, TabController tabs) async {
    if (!_current()) return;
    setState(() => _loading = true);
    try {
      final record = await WritingPracticeHistory.loadCase(
        widget.root,
        widget.book,
        id,
      );
      if (!mounted || !_current()) return;
      setState(() {
        _selected = record;
        _error = null;
      });
      tabs.animateTo(0);
    } catch (error) {
      if (mounted) setState(() => _error = '来源练习未能载入：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _loading || _saving;
    return PopScope(
      canPop: !_saving,
      child: DefaultTabController(
        length: 2,
        child: Builder(
          builder: (context) {
            final tabs = DefaultTabController.of(context);
            return AlertDialog(
              insetPadding: const EdgeInsets.all(16),
              title: const Text('练习记录与作品偏好'),
              content: SizedBox(
                width: 680,
                height: (MediaQuery.sizeOf(context).height - 220).clamp(
                  220.0,
                  700.0,
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('作品：${widget.book}'),
                    ),
                    const TabBar(tabs: [Tab(text: '练习回顾'), Tab(text: '作品偏好')]),
                    if (locked) const LinearProgressIndicator(),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_preferencesError != null)
                      Text(
                        _preferencesError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _selected == null
                              ? _list(locked)
                              : _detail(_selected!, locked),
                          _preferenceList(locked, tabs),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: locked ? null : () => _load(),
                  child: const Text('重新载入'),
                ),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _list(bool locked) => ListView(
    children: [
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('回看当时的目标、原稿和自改。记录不会自动成为作品偏好。'),
      ),
      if (!_loading && _records.isEmpty && _problems.isEmpty && _error == null)
        const Text('还没有练习记录。选中正文，完成「选段练笔」后保存即可。'),
      for (final record in _records)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${record.chapter} · ${record.goal.label}'),
          subtitle: Text(
            '${DateTime.parse(record.createdAt).toLocal()}\n${record.intention.isEmpty ? record.passage : record.intention}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: locked ? null : () => setState(() => _selected = record),
        ),
      if (_problems.isNotEmpty) ...[
        const Text('以下记录未能读取，原文件保留：'),
        for (final problem in _problems) SelectableText(problem),
      ],
      if (_cursor != null)
        TextButton(
          onPressed: locked ? null : () => _load(more: true),
          child: const Text('加载更早记录'),
        ),
    ],
  );

  Widget _detail(WritingPracticeCase record, bool locked) => ListView(
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: locked ? null : () => setState(() => _selected = null),
          child: const Text('返回记录列表'),
        ),
      ),
      Text(
        '${record.chapter} · ${record.goal.label}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Text('当时的模型：${record.model}'),
      if (record.intention.isNotEmpty) _section('本次意图', record.intention),
      if (record.authorGoal case final goal?)
        _section(
          '当时的作品目标（版本 ${goal.version}，${goal.enabled ? "启用" : "停用"}）',
          goal.enabled
              ? '${goal.target}\n保留：${goal.keep}\n避免：${goal.avoid}'
              : '当次未使用目标文字。',
        ),
      if (record.authorGoal == null) const Text('这份记录没有作品目标快照。'),
      if (record.preferences case final preferences?)
        _section(
          '当时的作品偏好（版本 ${preferences.version}）',
          preferences.active.isEmpty
              ? '当次没有生效偏好。'
              : preferences.active.map((item) => item.text).join('\n'),
        ),
      _section('原稿', record.passage),
      ..._feedback('原稿反馈（模型意见）', record.feedback),
      PracticeSourceDetails(
        title: '原稿反馈来源',
        root: widget.root,
        source: record.feedbackSource,
        isCurrent: widget.isCurrent,
      ),
      _section(
        '我的决定',
        {
          'pending': '尚未决定',
          'try': '尝试这个方向',
          'reject': '建议不适合',
          'defer': '暂时不处理',
        }[record.decision]!,
      ),
      if (record.revision.isNotEmpty) _section('我的改稿', record.revision),
      if (record.revisionFeedback case final feedback?)
        ..._feedback('改稿反馈（模型意见）', feedback),
      if (record.revisionFeedback != null)
        PracticeSourceDetails(
          title: '改稿复评来源',
          root: widget.root,
          source: record.revisionFeedbackSource,
          isCurrent: widget.isCurrent,
        ),
      if (record.reflection.isNotEmpty) _section('我的反思', record.reflection),
      const Text('希望后续继续遵循某项选择时，请用自己的话填写，再明确确认。仅对这部作品生效。'),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonal(
          onPressed:
              locked || _preferences == null ? null : () => _confirm(record),
          child: const Text('记住一项作品偏好'),
        ),
      ),
    ],
  );

  List<Widget> _feedback(String title, PracticeFeedback feedback) => [
    Text(title, style: Theme.of(context).textTheme.titleSmall),
    if (feedback.observations.isEmpty) const Text('当次没有可确认引用的反馈。'),
    for (final item in feedback.observations)
      _section(
        '“${item.quote}”',
        '${item.observation}\n依据：${item.reason}\n可试方向：${item.direction}\n练习：${item.exercise}${item.example.isEmpty ? "" : "\n可选示例：${item.example}"}',
      ),
  ];

  Widget _section(String title, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        SelectableText(text),
      ],
    ),
  );

  Widget _preferenceList(bool locked, TabController tabs) {
    final preferences = _preferences;
    if (preferences == null) {
      return const Center(child: Text('作品偏好尚未载入，请重新载入。'));
    }
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('仅用于新发起的选段练笔。本次意图与作品目标优先，冲突留给你决定。撤销会保留历史依据。'),
        ),
        Text('生效中：${preferences.active.length}/8'),
        if (preferences.items.isEmpty) const Text('还没有确认的偏好。可以从练习回顾中添加。'),
        for (final item in preferences.items.reversed)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(item.text),
                  Text(item.active ? '作者已确认' : '已撤销，后续新练笔不使用'),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed:
                            locked
                                ? null
                                : () => _source(item.sourceCaseId, tabs),
                        child: const Text('查看来源练习'),
                      ),
                      if (item.active)
                        TextButton(
                          onPressed: locked ? null : () => _revoke(item),
                          child: const Text('撤销偏好'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PreferenceConfirmation extends StatefulWidget {
  final String book;
  const _PreferenceConfirmation({required this.book});
  @override
  State<_PreferenceConfirmation> createState() => _ConfirmationState();
}

class _ConfirmationState extends State<_PreferenceConfirmation> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('确认作品偏好'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('只应用于《${widget.book}》的后续新练笔。请说明希望保留的写法，以及适用的情境；以后可撤销。'),
            TextField(
              key: const ValueKey('preference-text'),
              controller: _text,
              maxLength: 200,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: '我希望之后继续遵循的选择'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed:
            _text.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, _text.text.trim()),
        child: const Text('确认并记住'),
      ),
    ],
  );
}
