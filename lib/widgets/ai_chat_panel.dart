/// 聊天与斜杠命令共用当前草稿快照、总预算和同一传输契约。
library;

import '../api/api_client.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/direct_llm_client.dart';
import '../services/editor_request_lease.dart';
import '../services/editor_context_capture.dart';
import '../services/writing_assistant.dart';
import '../services/writing_context.dart';
import '../services/writing_candidate.dart';
import '../services/writing_request_ledger.dart';
import 'writing_candidate_preview.dart';
import 'writing_practice_dialog.dart';
import '../store/editor_store.dart';
import '../store/companion_store.dart';
import '../store/navigation_store.dart';
import '../theme/colors.dart';
import '../theme/motion.dart';
import '../theme/radius.dart';
import '../theme/spacing.dart';
import 'ai_actions.dart';
import 'pixel_companion.dart';
import 'pixel_companion_palette.dart' show CompanionState;
import 'pixel_companion_settings.dart';

/// 写作聊天面板。
class AiChatPanel extends ConsumerStatefulWidget {
  const AiChatPanel({super.key});

  @override
  ConsumerState<AiChatPanel> createState() => AiChatPanelState();
}

class AiChatPanelState extends ConsumerState<AiChatPanel> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  bool _sending = false;
  bool _receivedContent = false;
  EditorRequestLease? _requestLease;
  String? _contextDescription;
  final _comparisons =
      <String, ({WritingCandidate candidate, CandidateOriginWatch origin})>{};

  void _invalidateComparisons(String reason) {
    for (final item in _comparisons.values) {
      item.origin.invalidate(reason);
    }
    _pendingOrigin?.invalidate(reason);
  }

  CandidateOriginWatch? _pendingOrigin;

  bool get _requestIsCurrent => mounted && (_requestLease?.isCurrent ?? false);

  @override
  void dispose() {
    _invalidateComparisons('聊天已关闭；这份比较已失效。');
    for (final item in _comparisons.values) {
      item.origin.dispose();
    }
    _pendingOrigin?.dispose();
    _pendingOrigin = null;
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: Motion.fast,
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 把消息追加到 aiMessagesProvider 并滚动到底部
  void _appendMessage(ChatMessage msg) {
    if (!_requestIsCurrent) return;
    final msgs = [...ref.read(aiMessagesProvider), msg];
    ref.read(aiMessagesProvider.notifier).state = msgs;
    _scrollToBottom();
  }

  /// 更新最后一条 assistant 消息
  void _updateLastAssistant(String content, String reasoning) {
    if (!_requestIsCurrent) return;
    final current = [...ref.read(aiMessagesProvider)];
    if (current.isNotEmpty && current.last.role == 'assistant') {
      current[current.length - 1] = current.last.copyWith(
        content: content,
        reasoning: reasoning,
      );
      ref.read(aiMessagesProvider.notifier).state = current;
    }
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _requestLease = EditorRequestLease(ref);
    setState(() {
      _sending = true;
      _receivedContent = false;
    });
    var started = false;
    var acc = '';
    var reasoning = '';
    WritingRequestCompletion? completion;
    CandidateOriginWatch? origin;
    try {
      final source = EditorSourceSnapshot.capture(ref);
      final cmd = parseSlashCommand(text);
      if (cmd?.action == AiAction.rewrite ||
          cmd?.action == AiAction.continueWrite) {
        origin = CandidateOriginWatch(
          source,
          ref.read(editorControllerProvider)!.controller,
        );
        _pendingOrigin = origin;
      }
      late WritingContextPlan plan;
      var historyScopeChanged = false;
      if (cmd == null) {
        final budget = ref.read(aiContextStrategyProvider).maxChars;
        final direction = await source.loadDirection();
        if (!_requestIsCurrent) return;
        final messages = ref.read(aiMessagesProvider);
        final history = ChatMessage.recentContext(
          messages,
          directionKey: direction.historyKey,
        );
        historyScopeChanged =
            history.length < messages.where((m) => m.includeInContext).length;
        plan = source.plan(
          request: text,
          budget: budget,
          history: history,
          direction: direction,
        );
      } else {
        plan = await buildSlashContext(ref, source, cmd);
      }
      if (!_requestIsCurrent) return;
      final model = ref.read(selectedModelProvider);
      final useEngine = apiClient.supports('context_feedback');
      _appendMessage(
        ChatMessage(
          role: 'user',
          content: text,
          directionKey: plan.directionKey,
        ),
      );
      _appendMessage(
        ChatMessage(
          role: 'assistant',
          content: '',
          includeInContext: false,
          directionKey: plan.directionKey,
        ),
      );
      started = true;
      // Preserve anything the author typed while the direction file loaded.
      if (_inputCtrl.text.trim() == text) _inputCtrl.clear();
      setState(() {
        _contextDescription =
            '上次请求 · ${plan.description}'
            '${historyScopeChanged ? "作者方向变更前的对话未发送，原记录仍可查看。" : ""}';
      });
      ref.read(aiStreamingProvider.notifier).state = '';
      await for (final event in WritingAssistant.stream(
        plan: plan,
        model: model,
        useEngine: useEngine,
        onCompleted: (value) => completion = value,
      )) {
        if (!_requestIsCurrent) return;
        switch (event.type) {
          case DirectLlmEventType.content:
            if (!_receivedContent) setState(() => _receivedContent = true);
            acc += event.content;
            _updateLastAssistant(acc, reasoning);
            ref.read(aiStreamingProvider.notifier).state = acc;
            _scrollToBottom();
          case DirectLlmEventType.reasoning:
            reasoning += event.content;
            _updateLastAssistant(acc, reasoning);
          case DirectLlmEventType.error:
            throw StateError(event.content);
          case DirectLlmEventType.done:
            break;
        }
      }
      if (_requestIsCurrent && acc.isNotEmpty) {
        String? comparisonId;
        if (origin != null && completion != null) {
          try {
            final candidate = WritingCandidate.fromCompleted(
              source: source,
              plan: plan,
              completion: completion!,
              body: acc,
            );
            if (candidate != null) {
              comparisonId = completion!.requestId;
              if (_comparisons.length >= 8) {
                _comparisons.remove(_comparisons.keys.first)!.origin.dispose();
              }
              _comparisons[comparisonId] = (
                candidate: candidate,
                origin: origin,
              );
              _pendingOrigin = null;
              origin = null;
            }
          } on StateError {
            _contextDescription =
                '${_contextDescription ?? ""} 比较来源核对未通过，回复仍保留在本机记录中。';
          }
        }
        final messages = [...ref.read(aiMessagesProvider)];
        messages[messages.length - 1] = messages.last.copyWith(
          includeInContext: true,
          requestId: comparisonId,
        );
        ref.read(aiMessagesProvider.notifier).state = messages;
        ref.read(companionControllerProvider).setStateExt(CompanionState.happy);
      }
    } catch (error) {
      if (!mounted) return;
      if (_requestIsCurrent) {
        if (started) {
          ref
              .read(companionControllerProvider)
              .setStateExt(CompanionState.error);
          _updateLastAssistant(
            '${acc.isEmpty ? "" : "$acc\n\n"}生成中断：$error',
            reasoning,
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('未发送：$error')));
        }
      }
    } finally {
      // A disposed panel has already released the pending watch.
      if (identical(_pendingOrigin, origin) && origin != null) {
        _pendingOrigin = null;
        origin.dispose();
      }
      if (_requestIsCurrent) {
        ref.read(aiStreamingProvider.notifier).state = null;
      }
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 点击斜杠命令 chip 时: 直接填充到输入框 (用户可继续追加额外文本)
  void _fillSlashCommand(String cmd) {
    if (_sending) return;
    final current = _inputCtrl.text;
    _inputCtrl.text = current.isEmpty ? cmd : '$cmd $current';
    _inputCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputCtrl.text.length),
    );
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentBookProvider, (previous, next) {
      if (previous != next) _invalidateComparisons('作品已切换；旧比较已失效。');
    });
    ref.listen(currentChapterProvider, (previous, next) {
      if (previous != next) _invalidateComparisons('章节已切换；旧比较已失效。');
    });
    ref.listen(editorControllerProvider, (previous, next) {
      if (!identical(previous?.controller, next?.controller)) {
        _invalidateComparisons('编辑器已重新载入；旧比较已失效。');
      }
    });
    final msgs = ref.watch(aiMessagesProvider);
    final b = Theme.of(context).brightness;
    return Column(
      children: [
        _CompanionChatHeader(
          activity:
              _sending
                  ? (_receivedContent
                      ? CompanionState.speaking
                      : CompanionState.thinking)
                  : null,
        ),
        Expanded(
          child:
              msgs.isEmpty
                  ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(S.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (ref
                              .watch(companionControllerProvider)
                              .visible) ...[
                            PixelCompanionLive(
                              controller: ref.watch(
                                companionControllerProvider,
                              ),
                              size: 96,
                            ),
                            const SizedBox(height: S.md),
                          ],
                          Text(
                            '与 AI 聊天\n参考当前草稿，范围随预算显示\n\n选段练笔，或点击下方命令继续写作',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                  : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(S.sm),
                    itemCount: msgs.length,
                    itemBuilder: (ctx, i) {
                      final comparison = _comparisons[msgs[i].requestId];
                      return AiChatBubble(
                        msg: msgs[i],
                        onCompare:
                            comparison == null
                                ? null
                                : () {
                                  showDialog<void>(
                                    context: context,
                                    builder:
                                        (_) => WritingCandidatePreview(
                                          candidate: comparison.candidate,
                                          origin: comparison.origin,
                                        ),
                                  );
                                },
                      );
                    },
                  ),
        ),
        if (_contextDescription != null)
          Padding(
            padding: const EdgeInsets.all(S.sm),
            child: Text(
              _contextDescription!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        // D40: 斜杠命令 chips (单入口, 替代 4 外置按键)
        Container(
          padding: const EdgeInsets.fromLTRB(S.sm, S.xs, S.sm, 0),
          child: Wrap(
            spacing: 4,
            runSpacing: 0,
            children: [
              _SlashChip(
                label: '选段练笔',
                tooltip: '先选正文，再选一个目标，获得依据反馈并自己修改',
                onTap: () {
                  if (!_sending) showWritingPracticeDialog(context, ref);
                },
              ),
              _SlashChip(
                label: '/续写',
                tooltip: '基于上下文续写 100 字',
                onTap: () => _fillSlashCommand('/续写'),
              ),
              _SlashChip(
                label: '/建议',
                tooltip: '最多两处原句表达反馈',
                onTap: () => _fillSlashCommand('/建议'),
              ),
              _SlashChip(
                label: '/总结',
                tooltip: '总结实际提供的正文范围',
                onTap: () => _fillSlashCommand('/总结'),
              ),
              _SlashChip(
                label: '/改写',
                tooltip: '润色当前选区',
                onTap: () => _fillSlashCommand('/改写'),
              ),
              _SlashChip(
                label: '/检查',
                tooltip: '检查潜在问题',
                onTap: () => _fillSlashCommand('/检查'),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(S.sm, S.xs, S.sm, S.sm),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: AppPalette.divider(b), width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  focusNode: _inputFocus,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !_sending,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: '输入消息, 或点击上方命令',
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: S.sm,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.sm),
                      borderSide: BorderSide(color: AppPalette.divider(b)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.sm),
                      borderSide: BorderSide(color: AppPalette.divider(b)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.sm),
                      borderSide: const BorderSide(color: AppColors.ai),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: S.xs),
              IconButton(
                onPressed: _sending ? null : _send,
                icon:
                    _sending
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.send_rounded, size: 18),
                color: AppColors.ai,
                tooltip: '发送',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompanionChatHeader extends ConsumerWidget {
  final CompanionState? activity;
  const _CompanionChatHeader({this.activity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(companionControllerProvider);
    final state = activity ?? controller.state;
    final label = switch (state) {
      CompanionState.thinking => '等待回复',
      CompanionState.speaking => '正在回复',
      CompanionState.happy => '回复完成',
      CompanionState.error => '生成中断',
      _ => '随时开始写作',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xs),
      child: Row(
        children: [
          if (controller.visible) ...[
            Semantics(
              label: '写作伙伴，$label',
              image: true,
              child: PixelCompanionLive(
                controller: controller,
                size: 48,
                stateOverride: state,
              ),
            ),
            const SizedBox(width: S.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.visible
                      ? (controller.hasCustom
                          ? '写作伙伴'
                          : controller.currentCharacter?.name ?? '写作伙伴')
                      : '写作对话',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '写作伙伴设置',
            icon: const Icon(Icons.more_horiz, size: 18),
            onSelected: (value) {
              if (value == 'settings') {
                showCompanionSettingsSheet(context, controller);
              }
              if (value == 'preview') {
                ref
                    .read(navigationControllerProvider.notifier)
                    .push(AppRoute.companion);
              }
            },
            itemBuilder:
                (_) => const [
                  PopupMenuItem(value: 'settings', child: Text('伙伴设置')),
                  PopupMenuItem(value: 'preview', child: Text('动作预览')),
                ],
          ),
        ],
      ),
    );
  }
}

/// D40: 斜杠命令 chip
class _SlashChip extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  const _SlashChip({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.xs),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.ai.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(R.xs),
            border: Border.all(color: AppColors.ai.withValues(alpha: 0.25)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.ai,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// T-3: 单条聊天消息气泡
class AiChatBubble extends StatelessWidget {
  final ChatMessage msg;
  final VoidCallback? onCompare;
  const AiChatBubble({super.key, required this.msg, this.onCompare});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    final b = Theme.of(context).brightness;
    return Container(
      margin: const EdgeInsets.only(bottom: S.sm),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.aiGradientStart, AppColors.aiGradientEnd],
                ),
                borderRadius: BorderRadius.circular(R.xs),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 12,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: S.xs),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: S.sm,
                vertical: 8,
              ),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color:
                    isUser
                        ? AppColors.ai.withValues(alpha: 0.12)
                        : AppPalette.surfaceHigh(b),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isUser ? R.sm : 2),
                  topRight: Radius.circular(isUser ? 2 : R.sm),
                  bottomLeft: const Radius.circular(R.sm),
                  bottomRight: const Radius.circular(R.sm),
                ),
                border: Border.all(
                  color:
                      isUser
                          ? AppColors.ai.withValues(alpha: 0.3)
                          : AppPalette.divider(b),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(
                    msg.content.isEmpty ? '...' : msg.content,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.5,
                      color: isUser ? AppColors.ai : AppPalette.textPrimary(b),
                    ),
                  ),
                  if (!isUser && onCompare != null)
                    TextButton.icon(
                      onPressed: onCompare,
                      icon: const Icon(Icons.compare_arrows, size: 16),
                      label: const Text('只读比较'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
