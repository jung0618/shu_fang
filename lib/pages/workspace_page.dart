import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../store/local_prefs.dart';
import '../store/workspace_store.dart';

class WorkspacePage extends ConsumerStatefulWidget {
  const WorkspacePage({super.key});

  @override
  ConsumerState<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends ConsumerState<WorkspacePage> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final ok = await ref
        .read(workspaceControllerProvider.notifier)
        .create(_name.text);
    if (mounted && !ok) ref.invalidate(workspaceCatalogProvider);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceControllerProvider);
    final catalog = ref.watch(workspaceCatalogProvider);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.auto_stories_outlined,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '书坊',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '从一个故事开始，慢慢写出自己的文笔。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  Text('打开本机工作区', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    '正文和设定保存在下面的目录中。离线也能写作，无需注册。工作区用于整理本机作品，同一台电脑上的使用者仍可访问这些文件。',
                  ),
                  const SizedBox(height: 16),
                  catalog.when(
                    loading:
                        () => const Center(child: CircularProgressIndicator()),
                    error:
                        (error, stack) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('无法读取工作区目录：$error'),
                            TextButton(
                              onPressed:
                                  () =>
                                      ref.invalidate(workspaceCatalogProvider),
                              child: const Text('重新读取'),
                            ),
                          ],
                        ),
                    data:
                        (items) => Column(
                          children: [
                            for (final item in items)
                              Card(
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 10,
                                  ),
                                  leading: Icon(
                                    item.isPrimary
                                        ? Icons.home_work_outlined
                                        : Icons.folder_outlined,
                                  ),
                                  title: Text(
                                    '${item.name}${item.id == PrefsController.current.lastWorkspaceId ? ' · 最近使用' : ''}',
                                  ),
                                  subtitle: Text(item.path),
                                  trailing: const Icon(
                                    Icons.arrow_forward_rounded,
                                  ),
                                  enabled: !state.isLoading,
                                  onTap:
                                      () => ref
                                          .read(
                                            workspaceControllerProvider
                                                .notifier,
                                          )
                                          .open(item.id),
                                ),
                              ),
                          ],
                        ),
                  ),
                  const SizedBox(height: 24),
                  Text('新建工作区', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    enabled: !state.isLoading,
                    maxLength: 64,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      hintText: '例如：长篇创作、短篇练习',
                    ),
                    onSubmitted: (_) => _create(),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: state.isLoading ? null : _create,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('创建并开始写作'),
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: 16),
                    SelectableText(
                      state.error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
