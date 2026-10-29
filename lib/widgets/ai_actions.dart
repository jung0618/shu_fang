/// AI 命令与兼容动作入口，共用当前草稿快照与整体字符预算。
library;

import '../api/api_client.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/direct_llm_client.dart';
import '../services/editor_request_lease.dart';
import '../services/editor_context_capture.dart';
import '../services/writing_assistant.dart';
import '../services/writing_context.dart';
import '../store/editor_store.dart';

/// AI 面板模式 (T-3: 聊天切换)
enum AiPanelMode { quickActions, chat }

final aiPanelModeProvider = StateProvider<AiPanelMode>(
  (ref) => AiPanelMode.quickActions,
);

// ============================================================
// T-9: AI 快捷命令系统 (斜杠命令解析+分发)
// ============================================================

/// 快捷命令解析结果
class SlashCommand {
  final AiAction action;
  final String extra; // 命令后的额外文本 (如 /改写 更加生动 → "更加生动")
  const SlashCommand(this.action, this.extra);
}

/// T-9: 解析斜杠命令, 返回 null 表示不是命令
SlashCommand? parseSlashCommand(String text) {
  if (!text.startsWith('/')) return null;
  final trimmed = text.trim();
  final spaceIdx = trimmed.indexOf(' ');
  final cmd = spaceIdx > 0 ? trimmed.substring(0, spaceIdx) : trimmed;
  final extra = spaceIdx > 0 ? trimmed.substring(spaceIdx + 1).trim() : '';

  switch (cmd.toLowerCase()) {
    case '/续写':
    case '/continue':
      return SlashCommand(AiAction.continueWrite, extra);
    case '/改写':
    case '/rewrite':
      return SlashCommand(AiAction.rewrite, extra);
    case '/总结':
    case '/summary':
      return SlashCommand(AiAction.summary, extra);
    case '/建议':
    case '/检查':
    case '/suggest':
    case '/check':
      return SlashCommand(AiAction.suggest, extra);
    default:
      return null;
  }
}

/// The manuscript stays frozen; author choices are freshly loaded before each
/// request. Neither transport may add a different manuscript or hidden Lore.
Future<WritingContextPlan> buildSlashContext(
  WidgetRef ref,
  EditorSourceSnapshot source,
  SlashCommand cmd,
) async {
  final task = switch (cmd.action) {
    AiAction.continueWrite => WritingTask.continuation,
    AiAction.rewrite => WritingTask.revision,
    AiAction.summary => WritingTask.summary,
    AiAction.suggest => WritingTask.feedback,
    AiAction.chat => WritingTask.discussion,
  };
  final instruction = switch (cmd.action) {
    AiAction.continueWrite => '根据提供的正文续写约 100 字，保持人物认知、动机与叙事视角一致。',
    AiAction.rewrite => '优先改写标注选段，保留原意。只给可选示例和理由；若只有节选，不能声称已改写整章。',
    AiAction.summary => '只总结提供的正文事实。若材料是节选，在开头说明总结范围，不能补出缺失情节。',
    AiAction.suggest => '结合具体原句，最多指出两处表达问题、原因与可操作修改方向；证据不足时说明。',
    AiAction.chat => '围绕作者本轮目标讨论。',
  };
  final budget = ref.read(aiContextStrategyProvider).maxChars;
  final direction = await source.loadDirection();
  return source.plan(
    request:
        cmd.extra.isEmpty ? instruction : '$instruction\n作者补充要求：${cmd.extra}',
    budget: budget,
    task: task,
    direction: direction,
  );
}

typedef SlashStreamUpdate = void Function(String content, String reasoning);
typedef SlashStreamError = void Function(String error);

Future<void> dispatchSlashCommandToChat(
  WidgetRef ref,
  SlashCommand cmd, {
  required SlashStreamUpdate onUpdate,
  required SlashStreamError onError,
}) async {
  final lease = EditorRequestLease(ref);
  try {
    final source = EditorSourceSnapshot.capture(ref);
    final plan = await buildSlashContext(ref, source, cmd);
    if (!lease.isCurrent) return;
    var content = '';
    var reasoning = '';
    await for (final event in WritingAssistant.stream(
      plan: plan,
      model: ref.read(selectedModelProvider),
      useEngine: apiClient.supports('context_feedback'),
    )) {
      if (!lease.isCurrent) return;
      switch (event.type) {
        case DirectLlmEventType.content:
          content += event.content;
          onUpdate(content, reasoning);
        case DirectLlmEventType.reasoning:
          reasoning += event.content;
          onUpdate(content, reasoning);
        case DirectLlmEventType.error:
          onError(event.content);
          return;
        case DirectLlmEventType.done:
          return;
      }
    }
  } catch (error) {
    if (lease.isCurrent) onError('$error');
  }
}

Future<void> dispatchSlashCommand(WidgetRef ref, SlashCommand cmd) async {
  final lease = EditorRequestLease(ref);
  startAiAction(ref, cmd.action);
  var result = '';
  var reasoning = '';
  var failed = false;
  await dispatchSlashCommandToChat(
    ref,
    cmd,
    onUpdate: (text, thought) {
      result = text;
      reasoning = thought;
      if (lease.isCurrent) {
        ref.read(aiActionStateProvider.notifier).state = AiActionState(
          action: cmd.action,
          status: 'running',
          content: text,
          reasoning: thought,
        );
      }
    },
    onError: (error) {
      failed = true;
      if (lease.isCurrent) {
        ref.read(aiActionStateProvider.notifier).state = AiActionState(
          action: cmd.action,
          status: 'error',
          error: error,
        );
      }
    },
  );
  if (!failed && lease.isCurrent) {
    ref.read(aiActionStateProvider.notifier).state = AiActionState(
      action: cmd.action,
      status: 'done',
      content: result,
      reasoning: reasoning,
    );
  }
}

Future<void> runContinueWrite(WidgetRef ref) =>
    dispatchSlashCommand(ref, const SlashCommand(AiAction.continueWrite, ''));
Future<void> runSuggest(WidgetRef ref) =>
    dispatchSlashCommand(ref, const SlashCommand(AiAction.suggest, ''));
Future<void> runSummary(WidgetRef ref) =>
    dispatchSlashCommand(ref, const SlashCommand(AiAction.summary, ''));
Future<void> runRewrite(WidgetRef ref, {String? instruction}) =>
    dispatchSlashCommand(
      ref,
      SlashCommand(AiAction.rewrite, instruction ?? ''),
    );
