import '../api/api_client.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/direct_llm_client.dart';
import '../services/editor_context_capture.dart';
import '../services/editor_request_lease.dart';
import '../services/writing_assistant.dart';
import '../services/writing_goal.dart';
import '../services/writing_practice.dart';
import '../services/writing_preferences.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';
import 'writing_goal_panel.dart';
import 'writing_practice_history_dialog.dart';

void showWritingPracticeDialog(BuildContext context, WidgetRef ref) {
  try {
    final source = EditorSourceSnapshot.capture(ref);
    if (source.selectionStart == null || source.selectionEnd == null) {
      throw StateError('先在正文中选一段文字，再点击「选段练笔」。');
    }
    final length = source.selectionEnd! - source.selectionStart!;
    if (length < 10 || length > 1800) {
      throw StateError('请选取 10～1800 字符，集中练习一个表达目标。');
    }
    showDialog<void>(
      context: context,
      builder: (_) => WritingPracticeDialog(source: source),
    );
  } catch (error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }
}

class WritingPracticeDialog extends ConsumerStatefulWidget {
  final EditorSourceSnapshot source;
  const WritingPracticeDialog({super.key, required this.source});

  @override
  ConsumerState<WritingPracticeDialog> createState() =>
      _WritingPracticeDialogState();
}

class _WritingPracticeDialogState extends ConsumerState<WritingPracticeDialog> {
  final _intention = TextEditingController();
  final _revision = TextEditingController();
  final _reflection = TextEditingController();
  PracticeGoal _goal = PracticeGoal.dialogue;
  PracticeFeedback? _feedback;
  PracticeFeedback? _revisionFeedback;
  String? _feedbackModel;
  String? _revisionFeedbackModel;
  String? _error;
  String? _savedPath;
  String _decision = 'pending';
  bool _busy = false;
  bool _saving = false;
  String _reviewedRevision = '';
  bool _allowPopOnce = false;
  bool _confirmingClose = false;
  bool _goalReady = false;
  bool _goalDirty = false;
  AuthorWritingGoal? _authorGoal;
  AuthorWritingGoal? _feedbackAuthorGoal;
  WritingPreferences? _feedbackPreferences;
  late final EditorRequestLease _sourceLease;

  @override
  void initState() {
    super.initState();
    _sourceLease = EditorRequestLease(ref);
  }

  bool get _sourceIsCurrent =>
      mounted &&
      _sourceLease.isCurrent &&
      localDataSource.storageRoot == widget.source.root &&
      _sourceLease.book == widget.source.book &&
      _sourceLease.chapter == widget.source.chapter;

  String get _passage => widget.source.text.substring(
    widget.source.selectionStart!,
    widget.source.selectionEnd!,
  );

  bool get _hasUnsavedWork =>
      !_allowPopOnce &&
      _savedPath == null &&
      (_feedback != null ||
          _goalDirty ||
          _goal != PracticeGoal.dialogue ||
          _intention.text.trim().isNotEmpty ||
          _revision.text.trim().isNotEmpty ||
          _reflection.text.trim().isNotEmpty ||
          _decision != 'pending');

  Future<void> _requestClose() async {
    if (_busy || _saving || _confirmingClose || _allowPopOnce || !mounted) {
      return;
    }
    if (!_hasUnsavedWork) {
      Navigator.of(context).pop();
      return;
    }
    _confirmingClose = true;
    bool? discard;
    try {
      discard = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('放弃这次练笔？'),
              content: const Text('当前目标、意图、反馈或改稿还没有保存，关闭后会丢失。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('继续练习'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('放弃并关闭'),
                ),
              ],
            ),
      );
    } finally {
      _confirmingClose = false;
    }
    if (discard == true && mounted) {
      setState(() => _allowPopOnce = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  void dispose() {
    _intention.dispose();
    _revision.dispose();
    _reflection.dispose();
    super.dispose();
  }

  Future<void> _generate({bool compare = false}) async {
    if (!_goalReady || _busy || _saving) return;
    if (!_sourceIsCurrent) {
      setState(() => _error = '工作区或章节已切换，请重新打开练笔。');
      return;
    }
    final lease = EditorRequestLease(ref);
    if (!lease.isCurrent ||
        lease.book != widget.source.book ||
        lease.chapter != widget.source.chapter ||
        localDataSource.storageRoot != widget.source.root) {
      return;
    }
    final revision = _revision.text;
    if (compare && (revision.trim().isEmpty || revision.length > 1800)) {
      setState(() => _error = '请自行写下不超过 1800 字符的改稿，再复看。');
      return;
    }
    final model = ref.read(selectedModelProvider);
    final goal = _goal;
    final intention = _intention.text;
    final authorGoal = compare ? _feedbackAuthorGoal : _authorGoal;
    setState(() {
      _busy = true;
      _error = null;
      _savedPath = null;
    });
    try {
      final preferences =
          compare
              ? _feedbackPreferences
              : (await WritingPreferenceStore.load(
                widget.source.root,
                widget.source.book,
              )).snapshot;
      if (!mounted || !lease.isCurrent) return;
      final plan = WritingPracticeContext.build(
        passage: _passage,
        revision: compare ? revision : null,
        goal: goal,
        intention: intention,
        authorGoal: authorGoal,
        preferences: preferences,
        book: widget.source.book,
        chapter: widget.source.chapter,
        sourceId: widget.source.id,
        budget: ref.read(aiContextStrategyProvider).maxChars,
      );
      var response = '';
      await for (final event in WritingAssistant.stream(
        plan: plan,
        model: model,
        useEngine: apiClient.supports('context_feedback'),
      )) {
        if (!mounted || !lease.isCurrent) return;
        if (event.type == DirectLlmEventType.content) response += event.content;
        if (event.type == DirectLlmEventType.error) {
          throw StateError(event.content);
        }
        if (response.length > 24000) throw StateError('反馈过长，请重试。');
      }
      if (!mounted || !lease.isCurrent) return;
      final feedback = PracticeFeedback.parse(
        response,
        compare ? revision : _passage,
      );
      setState(() {
        if (compare) {
          _revisionFeedback = feedback;
          _reviewedRevision = revision;
          _revisionFeedbackModel = model;
        } else {
          _feedback = feedback;
          _revisionFeedback = null;
          _feedbackModel = model;
          _feedbackAuthorGoal = authorGoal;
          _feedbackPreferences = preferences;
          _decision = 'pending';
        }
      });
    } catch (error) {
      if (mounted && lease.isCurrent) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_feedback == null || _saving) return;
    final lease = EditorRequestLease(ref);
    if (!_sourceIsCurrent ||
        localDataSource.storageRoot != widget.source.root ||
        lease.book != widget.source.book ||
        lease.chapter != widget.source.chapter) {
      setState(() => _error = '工作区或章节已切换，请返回原章节后保存。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final path = await WritingPracticeStore.save(
        source: widget.source,
        goal: _goal,
        intention: _intention.text,
        passage: _passage,
        feedback: _feedback!,
        model: _feedbackModel!,
        revision: _revision.text,
        reflection: _reflection.text,
        decision: _decision,
        authorGoal: _feedbackAuthorGoal,
        preferences: _feedbackPreferences,
        revisionFeedback:
            _reviewedRevision == _revision.text ? _revisionFeedback : null,
        revisionFeedbackModel: _revisionFeedbackModel,
      );
      if (mounted && lease.isCurrent) setState(() => _savedPath = path);
    } catch (error) {
      if (mounted) setState(() => _error = '记录未保存：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Widget> _cards(BuildContext context, PracticeFeedback feedback) => [
    if (feedback.observations.isEmpty) const Text('模型没有给出可核验的具体问题，这不代表能力评定。'),
    for (final item in feedback.observations)
      Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: SelectableText(
                  '「${item.quote}」',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
              if (item.offsets.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '选段中出现 ${item.offsets.length} 次；没有自动定位。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 10),
              _feedbackLine(label: '观察', text: item.observation),
              _feedbackLine(label: '理由', text: item.reason),
              _feedbackLine(label: '方向', text: item.direction),
              _feedbackLine(label: '自练', text: item.exercise),
              if (item.example.isNotEmpty)
                ExpansionTile(
                  title: const Text('查看可选示例'),
                  children: [SelectableText(item.example)],
                ),
            ],
          ),
        ),
      ),
  ];

  Widget _feedbackLine({required String label, required String text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: text),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = _busy || _saving;
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = (viewport.width - 48).clamp(320.0, 720.0).toDouble();
    final dialogHeight = math.max(
      280.0,
      math.min(760.0, viewport.height - 160),
    );
    return PopScope(
      canPop: !locked && !_hasUnsavedWork,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || locked || _allowPopOnce) return;
        _requestClose();
      },
      child: AlertDialog(
        title: const Text('选段练笔'),
        content: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: ListView(
            children: [
              const Text('反馈对应打开练笔时的原稿快照。展示前会核对引用；判断是否有帮助仍由你决定。'),
              const Text('会参考这部作品已确认的偏好；可在顶部「更多操作」中回顾或撤销。反馈开始后，本次依据固定。'),
              const SizedBox(height: 12),
              SelectableText(_passage),
              WritingGoalPanel(
                root: widget.source.root,
                book: widget.source.book,
                locked: locked || _feedback != null,
                isCurrent: () => _sourceIsCurrent,
                onChanged: (goal, ready, dirty) {
                  if (!mounted) return;
                  setState(() {
                    _authorGoal = goal;
                    _goalReady = ready;
                    _goalDirty = dirty;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PracticeGoal>(
                value: _goal,
                decoration: const InputDecoration(labelText: '这次只练一个目标'),
                items: [
                  for (final goal in PracticeGoal.values)
                    DropdownMenuItem(value: goal, child: Text(goal.label)),
                ],
                onChanged:
                    locked || _feedback != null
                        ? null
                        : (goal) => setState(() => _goal = goal!),
              ),
              TextField(
                controller: _intention,
                enabled: !locked && _feedback == null,
                maxLength: 400,
                maxLines: 2,
                onChanged: (_) => setState(() => _savedPath = null),
                decoration: const InputDecoration(labelText: '你想让读者感受到什么？（可选）'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed:
                      locked || !_goalReady || _feedback != null
                          ? null
                          : () => _generate(),
                  child: const Text('获取原句反馈'),
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_feedback != null) ...[
                ..._cards(context, _feedback!),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _decision,
                  decoration: const InputDecoration(labelText: '你对这次建议的决定'),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('尚未决定')),
                    DropdownMenuItem(value: 'try', child: Text('尝试这个方向')),
                    DropdownMenuItem(value: 'reject', child: Text('建议不适合')),
                    DropdownMenuItem(value: 'defer', child: Text('暂时不处理')),
                  ],
                  onChanged:
                      locked
                          ? null
                          : (value) => setState(() {
                            _decision = value!;
                            _savedPath = null;
                          }),
                ),
                TextField(
                  controller: _revision,
                  enabled: !locked,
                  maxLength: 1800,
                  minLines: 4,
                  maxLines: 10,
                  onChanged:
                      (_) => setState(() {
                        _savedPath = null;
                      }),
                  decoration: const InputDecoration(
                    labelText: '自己改一版（保存在练习记录中）',
                  ),
                ),
                TextField(
                  controller: _reflection,
                  enabled: !locked,
                  maxLength: 800,
                  maxLines: 3,
                  onChanged: (_) => setState(() => _savedPath = null),
                  decoration: const InputDecoration(
                    labelText: '为什么这样改？还有什么不确定？',
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: locked ? null : () => _generate(compare: true),
                    child: const Text('复看我的改稿'),
                  ),
                ),
                if (_revisionFeedback != null &&
                    _reviewedRevision == _revision.text) ...[
                  const Text('改稿反馈（模型意见）'),
                  ..._cards(context, _revisionFeedback!),
                ],
              ],
              if (_error != null)
                SelectableText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_savedPath != null) ...[
                const Text('练习已保存。记录中的改稿不会自动替换正文。'),
                TextButton(
                  onPressed: () => showWritingPracticeHistory(context, ref),
                  child: const Text('回顾练习与作品偏好'),
                ),
                SelectableText(_savedPath!),
                TextButton(
                  onPressed:
                      () => Clipboard.setData(ClipboardData(text: _savedPath!)),
                  child: const Text('复制记录路径'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: locked ? null : _requestClose,
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed:
                locked || _feedback == null || _savedPath != null
                    ? null
                    : _save,
            child: Text(_saving ? '保存中…' : '保存这次练习'),
          ),
        ],
      ),
    );
  }
}
