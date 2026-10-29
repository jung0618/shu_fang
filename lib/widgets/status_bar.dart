import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../store/editor_store.dart';
import '../theme/theme.dart';
import '../utils/word_counter.dart';

/// 字数统计防抖 Provider — E 阶段优化
/// 避免每次按键都跑 WordCounter.count (大文档会卡)
/// 500ms 防抖后更新字数
final _wordCountProvider = StateProvider<int>((ref) => 0);

/// 字数防抖控制器 (全局单例 Timer)
Timer? _wordCountDebounceTimer;

void cancelWordCountDebounce() {
  _wordCountDebounceTimer?.cancel();
  _wordCountDebounceTimer = null;
}

/// 更新字数 (防抖 500ms)
void updateWordCountDebounced(WidgetRef ref, String text) {
  _wordCountDebounceTimer?.cancel();
  final counter = ref.read(_wordCountProvider.notifier);
  _wordCountDebounceTimer = Timer(const Duration(milliseconds: 500), () {
    if (counter.mounted) counter.state = WordCounter.count(text);
  });
}

/// 直接设置字数 (无防抖, 用于初始化/章节切换)
void setWordCount(WidgetRef ref, String text) {
  _wordCountDebounceTimer?.cancel();
  ref.read(_wordCountProvider.notifier).state = WordCounter.count(text);
}

/// 底部状态栏 — 重新设计
/// E 阶段: 字数统计改为防抖 500ms, 避免每次按键重算
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    final bookInfo = ref.watch(currentBookInfoProvider);
    final chapterInfo = ref.watch(currentChapterInfoProvider);
    // E 阶段: 只 watch 字数 (防抖后的值), 不 watch 全文
    final wordCount = ref.watch(_wordCountProvider);
    final saveStatus = ref.watch(saveStatusProvider);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: S.lg),
      decoration: BoxDecoration(
        color: AppPalette.surface(b),
        border: Border(top: BorderSide(color: AppPalette.divider(b), width: 1)),
      ),
      child: Row(
        children: [
          // 字数统计
          Icon(
            Icons.text_fields_rounded,
            size: 11,
            color: AppPalette.textTertiary(b),
          ),
          const SizedBox(width: S.xs),
          Text(
            '总字数 ${WordCounter.format(wordCount)}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppPalette.textSecondary(b),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const ToolbarDivider(),
          // 保存状态
          _SaveIndicator(status: saveStatus),
          const Spacer(),
          // 当前位置
          if (bookInfo != null) ...[
            Icon(
              Icons.book_outlined,
              size: 11,
              color: AppPalette.textTertiary(b),
            ),
            const SizedBox(width: S.xs),
            Text(
              bookInfo.name,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textSecondary(b),
              ),
            ),
            if (chapterInfo != null) ...[
              Icon(
                Icons.chevron_right_rounded,
                size: 11,
                color: AppPalette.textTertiary(b),
              ),
              Text(
                chapterInfo.title,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textPrimary(b),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SaveIndicator extends StatelessWidget {
  final SaveStatus status;
  const _SaveIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == SaveStatus.idle) {
      return const SizedBox.shrink();
    }
    final (icon, text, color) = switch (status) {
      SaveStatus.unsaved => (
        Icons.edit_outlined,
        '待保存',
        Theme.of(context).colorScheme.primary,
      ),
      SaveStatus.saving => (Icons.sync_rounded, '保存中…', AppColors.primary),
      SaveStatus.saved => (
        Icons.check_circle_rounded,
        '已保存',
        AppColors.success,
      ),
      SaveStatus.error => (
        Icons.error_outline_rounded,
        '保存失败',
        AppColors.error,
      ),
      _ => (Icons.circle, '', AppColors.primary),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
