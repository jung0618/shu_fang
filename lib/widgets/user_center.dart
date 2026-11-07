/// Local workspace details and engine connection.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine_connection_panel.dart';
import '../store/workspace_store.dart';
import '../theme/colors.dart';
import '../theme/radius.dart';
import '../theme/spacing.dart';

/// 用户中心入口 (点击头像/用户名触发)
Future<void> showUserCenter(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _UserCenterDialog(),
  );
}

class _UserCenterDialog extends ConsumerStatefulWidget {
  const _UserCenterDialog();

  @override
  ConsumerState<_UserCenterDialog> createState() => _UserCenterDialogState();
}

class _UserCenterDialogState extends ConsumerState<_UserCenterDialog> {
  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final user = ref.watch(currentWorkspaceProvider);
    final workspaceState = ref.watch(workspaceControllerProvider);

    return Dialog(
      backgroundColor: AppPalette.surface(b),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.lg)),
      child: Container(
        width: 480,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        padding: const EdgeInsets.all(S.xl),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题
              Row(
                children: [
                  Icon(
                    Icons.account_circle_rounded,
                    size: 28,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: S.md),
                  Text('工作区与工具', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: S.lg),
              // 工作区信息
              _Section(
                title: '本机工作区',
                child: Column(
                  children: [
                    _Row(
                      icon: Icons.person_rounded,
                      label: '名称',
                      value: user?.name ?? '(未选择)',
                    ),
                    _Row(
                      icon: Icons.badge_rounded,
                      label: '存储方式',
                      value: '本机文件',
                    ),
                    _Row(
                      icon: Icons.shield_outlined,
                      label: '目录类型',
                      value: user?.isPrimary == true ? '主目录（兼容原有稿件）' : '独立子目录',
                    ),
                    _Row(
                      icon: Icons.folder_special_rounded,
                      label: '数据目录',
                      value: _storagePath(),
                      copyable: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: S.lg),
              const _Section(title: '写作引擎', child: EngineConnectionPanel()),
              const SizedBox(height: S.lg),
              if (workspaceState.error != null) ...[
                Text(
                  workspaceState.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: S.sm),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      workspaceState.isLoading
                          ? null
                          : () async {
                            await ref
                                .read(workspaceControllerProvider.notifier)
                                .leave();
                          },
                  icon: const Icon(Icons.drive_file_move_outline, size: 16),
                  label: const Text('保存并切换工作区'),
                ),
              ),
              const SizedBox(height: S.sm),
              // 底部说明
              Center(
                child: Text(
                  '本地写作与学习',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppPalette.textTertiary(b),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _storagePath() => ref.read(currentWorkspaceProvider)?.path ?? '-';
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(S.lg),
      decoration: BoxDecoration(
        color: AppPalette.surfaceHigh(b),
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppPalette.divider(b)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppPalette.textSecondary(b),
            ),
          ),
          const SizedBox(height: S.md),
          child,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool copyable;

  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.copyable = false,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: AppPalette.textTertiary(b)),
          const SizedBox(width: S.sm),
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.textTertiary(b),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: copyable ? 'monospace' : null,
                fontSize: copyable ? 11 : 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (copyable)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 12),
              tooltip: '复制',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}
