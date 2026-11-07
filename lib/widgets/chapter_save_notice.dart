import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/chapter_save_queue.dart';
import '../store/editor_store.dart' show chapterSaveQueueProvider;

/// Shown for the actual pane's address, including split editors.
class ChapterSaveNotice extends ConsumerWidget {
  final ChapterAddress address;
  const ChapterSaveNotice({super.key, required this.address});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(chapterSaveQueueProvider);
    final problem = queue.problemFor(address);
    if (problem == null) return const SizedBox.shrink();
    final message = switch (problem) {
      ChapterSaveProblem.diskChanged => '磁盘正文已变化，已阻止覆盖。请先复制当前正文，再核对外部版本。',
      ChapterSaveProblem.baselineMissing =>
        '缺少加载时的磁盘版本，已阻止保存。请先复制当前正文，再核对磁盘版本。',
      ChapterSaveProblem.unavailable => '未能确认保存完成，请检查文件与磁盘后手动重试。当前正文尚未确认保存。',
    };
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: colors.errorContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: TextStyle(color: colors.onErrorContainer)),
          const SizedBox(height: 6),
          Text(
            '草稿仅保留在本次应用会话中，退出前请另行保留。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onErrorContainer),
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: const Text('复制当前正文'),
            onPressed: () async {
              final text = queue.draftFor(address);
              if (text == null) return;
              String feedback;
              try {
                await Clipboard.setData(ClipboardData(text: text));
                feedback = '已复制当前正文；保存问题仍需核对。';
              } catch (_) {
                feedback = '复制未完成，请在编辑区选取正文后手动复制。';
              }
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(feedback)));
            },
          ),
        ],
      ),
    );
  }
}
