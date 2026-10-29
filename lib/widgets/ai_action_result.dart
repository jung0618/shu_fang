/// AI 操作结果展示 (T-8: running/done/error) + 单条建议展示 (T-4)
///
/// 从 ai_context_panel.dart 拆出. 由 AiContextPanel 在 quickActions 模式下展示.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../store/editor_store.dart';
import '../theme/colors.dart';
import '../theme/radius.dart';
import '../theme/spacing.dart';

/// T-8: AI 操作结果展示 (running/done/error)
class AiActionResult extends ConsumerWidget {
  final AiActionState state;
  const AiActionResult({super.key, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    return Container(
      margin: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, 0),
      padding: const EdgeInsets.all(S.md),
      decoration: BoxDecoration(
        color: AppPalette.surfaceHigh(b),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppPalette.divider(b)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, ref),
          const SizedBox(height: S.sm),
          _buildBody(context, ref),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final label = switch (state.action) {
      AiAction.continueWrite => '续写',
      AiAction.suggest => '建议',
      AiAction.summary => '总结',
      AiAction.rewrite => '改写',
      AiAction.chat => '聊天',
    };
    final (icon, color) = switch (state.status) {
      'running' => (Icons.hourglass_top_rounded, AppColors.warning),
      'done' => (Icons.check_circle_rounded, AppColors.success),
      'error' => (Icons.error_outline_rounded, AppColors.error),
      _ => (Icons.help_outline_rounded, AppPalette.textSecondary(Theme.of(context).brightness)),
    };
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text('$label · ${state.status == 'running' ? '生成中...' : state.status == 'done' ? '完成' : state.status == 'error' ? '失败' : state.status}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
        const Spacer(),
        if (state.status == 'done' || state.status == 'error')
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 14),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () => resetAiAction(ref),
          ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref) {
    if (state.status == 'running') {
      return Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.content.isEmpty ? '正在请求 AI...' : '已生成 ${state.content.length} 字',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    }
    if (state.status == 'error') {
      return Text(
        state.error.isEmpty ? '未知错误' : state.error,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error),
      );
    }
    // done
    // V4 reasoning 折叠展示 (T-7)
    Widget? reasoningWidget;
    if (state.reasoning.isNotEmpty) {
      reasoningWidget = ExpansionTile(
        tilePadding: EdgeInsets.zero,
        dense: true,
        title: Text('推理过程 (${state.reasoning.length} 字)', style: Theme.of(context).textTheme.labelSmall),
        children: [
          Container(
            padding: const EdgeInsets.all(S.sm),
            decoration: BoxDecoration(
              color: AppPalette.surface(Theme.of(context).brightness),
              borderRadius: BorderRadius.circular(R.xs),
            ),
            child: SelectableText(
              state.reasoning,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
        ],
      );
    }

    // 建议 (suggestions) 列表展示
    if (state.action == AiAction.suggest && state.suggestions.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reasoningWidget != null) reasoningWidget,
          for (int i = 0; i < state.suggestions.length; i++)
            SuggestionItem(
              item: state.suggestions[i],
              index: i + 1,
              onInsert: (text) => _insertText(ref, text),
            ),
        ],
      );
    }

    // 续写/总结/改写: content 文本 + 插入按钮
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reasoningWidget != null) reasoningWidget,
        if (state.content.isEmpty)
          Text('AI 未返回内容', style: Theme.of(context).textTheme.bodySmall)
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(S.sm),
            decoration: BoxDecoration(
              color: AppPalette.surface(Theme.of(context).brightness),
              borderRadius: BorderRadius.circular(R.xs),
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: SelectableText(
                state.content,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6),
              ),
            ),
          ),
          const SizedBox(height: S.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _insertText(ref, state.content),
                icon: const Icon(Icons.edit_rounded, size: 14),
                label: const Text('插入到编辑器'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: 4),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 设置 pendingInsertProvider, 编辑器会自动消费并插入到光标位置
  void _insertText(WidgetRef ref, String text) {
    if (text.isEmpty) return;
    ref.read(pendingInsertProvider.notifier).state = text;
  }
}

/// T-4: 单条建议展示
class SuggestionItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final int index;
  final void Function(String text) onInsert;
  const SuggestionItem({super.key, required this.item, required this.index, required this.onInsert});

  @override
  Widget build(BuildContext context) {
    final title = item['title']?.toString() ?? '建议 $index';
    final content = item['content']?.toString() ?? '';
    final category = item['category']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(S.sm),
      decoration: BoxDecoration(
        color: AppPalette.surface(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(R.xs),
        border: Border.all(color: AppPalette.divider(Theme.of(context).brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.xs),
                ),
                child: Text(
                  '$index',
                  style: TextStyle(fontSize: 10, color: AppColors.warning, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              if (category.isNotEmpty)
                Text(
                  category,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.textTertiary(Theme.of(context).brightness),
                      ),
                ),
              const Spacer(),
              if (content.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 12),
                  tooltip: '插入到编辑器',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  onPressed: () => onInsert(content),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              content,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
