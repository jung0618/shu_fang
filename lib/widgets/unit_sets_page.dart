import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_routes.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';
import 'unit_set_detail_page.dart';
import 'unit_set_create_dialog.dart';

/// 单元集列表页
/// 注意: 单元集是引擎端概念 (存储在引擎 sqlite), 强依赖 HTTP
/// 引擎未启动时列表为空, 显示明确提示而非空状态, 避免用户误以为"自己没创建过"
class UnitSetsPage extends ConsumerStatefulWidget {
  const UnitSetsPage({super.key});

  @override
  ConsumerState<UnitSetsPage> createState() => _UnitSetsPageState();
}

class _UnitSetsPageState extends ConsumerState<UnitSetsPage> {
  bool? _engineReady;

  @override
  void initState() {
    super.initState();
    _checkEngine();
  }

  Future<void> _checkEngine() async {
    final ok = await LocalDataSource.isEngineReachable();
    if (mounted) setState(() => _engineReady = ok);
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final setsAsync = ref.watch(unitSetsProvider);
    final validateAsync = ref.watch(unitrefValidateProvider);
    final changesAsync = ref.watch(unitrefChangesProvider);
    final engineBlocked = _engineReady == false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('单元集'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              ref.invalidate(unitSetsProvider);
              ref.invalidate(unitrefChangesProvider);
              ref.invalidate(unitrefValidateProvider);
              _checkEngine();
            },
          ),
          // 引擎不可达时禁用新建按钮 (新建需要引擎支持)
          IconButton(
            icon: Icon(
              Icons.add,
              color: engineBlocked ? Theme.of(context).disabledColor : null,
            ),
            tooltip: engineBlocked ? '引擎未启动, 无法新建' : '新建',
            onPressed: engineBlocked
                ? null
                : () => showDialog(
                    context: context,
                    builder: (_) => const UnitSetCreateDialog(),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 引擎状态提示条
          if (engineBlocked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 14,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '引擎未启动 — 单元集是引擎端功能, 请先启动 ShuFang 全局启动器',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          // 状态条：变更检测
          changesAsync.when(
            data: (changes) => changes.isEmpty
                ? const SizedBox.shrink()
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_active, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${changes.length} 个单元集需要刷新',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            ref.invalidate(unitSetsProvider);
                            ref.invalidate(unitrefChangesProvider);
                          },
                          child: const Text('已处理'),
                        ),
                      ],
                    ),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
          ),
          // 校验状态 (引擎挂掉时隐藏)
          if (!engineBlocked)
            validateAsync.when(
              data: (v) {
                final valid = v['valid'] == true;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  color: valid
                      ? Colors.green.withValues(alpha: 0.1)
                      : Theme.of(context).colorScheme.errorContainer,
                  child: Row(
                    children: [
                      Icon(valid ? Icons.verified : Icons.warning_amber,
                          size: 14,
                          color: valid ? Colors.green : Theme.of(context).colorScheme.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          v['message'] as String? ?? (valid ? '路径校验通过' : '存在错误'),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
            ),
          // 列表
          Expanded(
            child: setsAsync.when(
              data: (sets) {
                if (sets.isEmpty) {
                  // 引擎未启动: 显示明确提示, 避免用户误以为"自己没创建过"
                  if (engineBlocked) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off, size: 48,
                              color: Theme.of(context).disabledColor),
                          const SizedBox(height: 12),
                          const Text('引擎未启动'),
                          const SizedBox(height: 4),
                          Text(
                            '单元集存储在引擎端, 需启动 ShuFang 全局启动器后使用',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).disabledColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.layers_outlined, size: 48),
                        const SizedBox(height: 12),
                        const Text('尚未创建任何单元集'),
                        const SizedBox(height: 4),
                        Text(
                          '可通过右上角 + 创建，或先在设定文件页签导入',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).disabledColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => const UnitSetCreateDialog(),
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('创建第一个单元集'),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(unitSetsProvider);
                    ref.invalidate(unitrefChangesProvider);
                    ref.invalidate(unitrefValidateProvider);
                  },
                  child: ListView.separated(
                    itemCount: sets.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final s = sets[i];
                      // 漂移避让: 默认态显示 📚 + 单元集名称, 悬停后向左漂移揭示完整信息
                      // 点击行为不变 (仍导航到详情页, 操作按钮在 reveal 层内)
                      return GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                UnitSetDetailPage(setId: s.id),
                          ),
                        ),
                        child: SizedBox(
                          height: 88,
                          // Phase 3.5b: 移除 DriftReveal (DriftReveal 仅用于主页快速入口条)
                          // 单元集卡直接显示完整信息, 无悬停切换
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    // 区别于设定集的 emoji 卡片:
                                    // 单元集用紫色图标块, 强调"引擎端结构化数据"
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFAB47BC).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: const Color(0xFFAB47BC).withValues(alpha: 0.4),
                                          width: 1,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.inventory_2_rounded,
                                        size: 18,
                                        color: Color(0xFFAB47BC),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        s.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                        onSelected: (v) async {
                                          switch (v) {
                                            case 'edit':
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      UnitSetDetailPage(
                                                          setId: s.id),
                                                ),
                                              );
                                              break;
                                            case 'delete':
                                              final confirm =
                                                  await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) =>
                                                    AlertDialog(
                                                  title: const Text('确认删除'),
                                                  content: Text(
                                                      '确定删除单元集「${s.name}」？'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, false),
                                                      child: const Text('取消'),
                                                    ),
                                                    FilledButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, true),
                                                      child: const Text('删除'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirm == true) {
                                                try {
                                                  // D38: 校验 res.ok (之前不查, 删除失败也刷新列表)
                                                  final res = await apiClient.delete(
                                                      ApiRoutes.unitSet(s.id));
                                                  if (!res.ok) {
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('删除失败: ${res.message.isEmpty ? "未知错误" : res.message}')),
                                                      );
                                                    }
                                                    return;
                                                  }
                                                  ref.invalidate(
                                                      unitSetsProvider);
                                                } catch (e) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                          content: Text(
                                                              '删除失败: $e')),
                                                    );
                                                  }
                                                }
                                              }
                                              break;
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                              value: 'edit',
                                              child: Text('编辑')),
                                          PopupMenuItem(
                                              value: 'delete',
                                              child: Text('删除')),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      if (s.description.isNotEmpty)
                                        s.description,
                                      '${s.chapterCount} 章 / ${s.settingCount} 设定',
                                      if (s.compression != null)
                                        '压缩 ${s.compression!['ratio'] ?? '-'}',
                                    ].join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.orange),
                    const SizedBox(height: 12),
                    Text('加载失败: $e', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        ref.invalidate(unitSetsProvider);
                        ref.invalidate(unitrefChangesProvider);
                        ref.invalidate(unitrefValidateProvider);
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
