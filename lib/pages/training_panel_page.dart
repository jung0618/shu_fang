// =============================================================================
// D49: 训练面板页 — 读取本地 training_rules.json 副本, 不依赖引擎 HTTP
// =============================================================================
// 设计目标:
//   - 训练成果 (规则/约束/摘要) 持久化到 {STORAGE_ROOT}/.hermes/training_rules.json
//   - Flutter 端直接读本地文件, 引擎未启动也可查看
//   - 引擎在线时可点"从引擎同步"触发 POST /api/evolution/export 刷新副本
//   - 面向开发者 (用户面不需要看训练细节)
//
// 数据来源:
//   1. 本地文件: {STORAGE_ROOT}/.hermes/training_rules.json (由后端 export_to_storage 生成)
//   2. 引擎在线时: POST /api/evolution/export 触发后端重新导出
// -----------------------------------------------------------------------------

library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_routes.dart';
import '../components/app_components.dart';
import '../store/local_data_source.dart';
import '../theme/colors.dart';
import '../theme/radius.dart';
import '../theme/spacing.dart';

/// 训练规则 JSON 副本的数据模型
class TrainingRulesExport {
  final int version;
  final int exportedAt;
  final int rulesCount;
  final List<TrainingRule> rules;
  final String constraintPrompt;
  final Map<String, dynamic> trainingSummary;

  const TrainingRulesExport({
    this.version = 1,
    this.exportedAt = 0,
    this.rulesCount = 0,
    this.rules = const [],
    this.constraintPrompt = '',
    this.trainingSummary = const {},
  });

  factory TrainingRulesExport.fromJson(Map<String, dynamic> json) {
    return TrainingRulesExport(
      version: json['version'] as int? ?? 1,
      exportedAt: json['exported_at'] as int? ?? 0,
      rulesCount: json['rules_count'] as int? ?? 0,
      rules: (json['rules'] as List?)
              ?.map((r) => TrainingRule.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      constraintPrompt: json['constraint_prompt'] as String? ?? '',
      trainingSummary:
          json['training_summary'] as Map<String, dynamic>? ?? {},
    );
  }
}

class TrainingRule {
  final String id;
  final String priority;
  final String category;
  final String instruction;
  final double weight;
  final String source;
  final String scope;

  const TrainingRule({
    required this.id,
    this.priority = 'medium',
    this.category = 'general',
    this.instruction = '',
    this.weight = 0.5,
    this.source = '',
    this.scope = 'global',
  });

  factory TrainingRule.fromJson(Map<String, dynamic> json) {
    return TrainingRule(
      id: json['id'] as String? ?? '',
      priority: json['priority'] as String? ?? 'medium',
      category: json['category'] as String? ?? 'general',
      instruction: json['instruction'] as String? ?? '',
      weight: (json['weight'] as num?)?.toDouble() ?? 0.5,
      source: json['source'] as String? ?? '',
      scope: json['scope'] as String? ?? 'global',
    );
  }
}

/// 训练规则副本 Provider (读本地文件, 不依赖引擎)
final trainingRulesProvider =
    FutureProvider.autoDispose<TrainingRulesExport?>((ref) async {
  final root = localDataSource.storageRoot;
  final path = '$root${Platform.pathSeparator}.hermes${Platform.pathSeparator}training_rules.json';
  final file = File(path);
  if (!await file.exists()) return null;
  try {
    final raw = await file.readAsString();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return TrainingRulesExport.fromJson(json);
  } catch (_) {
    return null;
  }
});

class TrainingPanelPage extends ConsumerStatefulWidget {
  const TrainingPanelPage({super.key});

  @override
  ConsumerState<TrainingPanelPage> createState() => _TrainingPanelPageState();
}

class _TrainingPanelPageState extends ConsumerState<TrainingPanelPage> {
  bool _autoSynced = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(trainingRulesProvider);
    // D52: 引擎在线且本地无副本时, 自动同步一次 (不阻塞 UI)
    async.whenData((export) {
      if (export == null && !_autoSynced) {
        _autoSynced = true;
        _tryAutoSync();
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('训练面板'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: '从引擎同步 (重新导出)',
            onPressed: () => _syncFromEngine(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新本地副本',
            onPressed: () => ref.invalidate(trainingRulesProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (export) => export == null
            ? _EmptyState(onSync: () => _syncFromEngine(context, ref))
            : _TrainingContent(export: export),
      ),
    );
  }

  /// D52: 静默自动同步 (引擎离线时不弹提示)
  Future<void> _tryAutoSync() async {
    try {
      final res = await apiClient.post(ApiRoutes.evolutionExport);
      if (res.ok && mounted) {
        ref.invalidate(trainingRulesProvider);
      }
    } catch (_) {
      // 引擎离线, 静默忽略
    }
  }

  /// 触发后端重新导出训练规则到本地文件
  Future<void> _syncFromEngine(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await apiClient.post(ApiRoutes.evolutionExport);
      if (!context.mounted) return;
      if (res.ok) {
        final count = res.data?['rules_count'] ?? 0;
        messenger.showSnackBar(
          SnackBar(
            content: Text('同步成功 ($count 条规则)'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.invalidate(trainingRulesProvider);
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('同步失败: ${res.message}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('引擎未启动或同步失败: $e'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// 空状态 — 本地无 training_rules.json 副本
class _EmptyState extends StatelessWidget {
  final VoidCallback onSync;
  const _EmptyState({required this.onSync});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(S.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined, size: 48, color: AppColors.primary.withValues(alpha: 0.5)),
            const SizedBox(height: S.md),
            Text('暂无训练规则副本',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: S.xs),
            Text(
              '训练规则由引擎导出到本地 .hermes/training_rules.json。\n引擎在线时点"从引擎同步"即可生成副本, 之后不依赖引擎也可查看。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppPalette.textTertiary(b)),
            ),
            const SizedBox(height: S.lg),
            FilledButton.icon(
              onPressed: onSync,
              icon: const Icon(Icons.sync_rounded, size: 16),
              label: const Text('从引擎同步'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 训练内容主体 — 摘要 + 约束提示(可折叠) + 规则列表
class _TrainingContent extends StatelessWidget {
  final TrainingRulesExport export;
  const _TrainingContent({required this.export});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    // 统计
    final byCategory = <String, int>{};
    final byPriority = <String, int>{};
    for (final r in export.rules) {
      byCategory[r.category] = (byCategory[r.category] ?? 0) + 1;
      byPriority[r.priority] = (byPriority[r.priority] ?? 0) + 1;
    }
    final exportedTime = export.exportedAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(export.exportedAt * 1000)
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.xl, S.xxl),
      children: [
        // 摘要卡 (含训练状态 + 注入状态)
        AppCard(
          padding: const EdgeInsets.all(S.md),
          color: AppColors.primary.withValues(alpha: 0.06),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.model_training_rounded,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: S.sm),
                  Text('训练规则摘要',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                  const Spacer(),
                  // D52: 注入状态标识
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 10, color: AppColors.success),
                        const SizedBox(width: 3),
                        Text('已注入 AI',
                            style: TextStyle(
                                fontSize: 9,
                                color: AppColors.success,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.sm),
              _SummaryRow(label: '规则总数', value: '${export.rulesCount}'),
              if (exportedTime != null)
                _SummaryRow(
                    label: '导出时间',
                    value: '${exportedTime.year}-${exportedTime.month.toString().padLeft(2, '0')}-${exportedTime.day.toString().padLeft(2, '0')} ${exportedTime.hour.toString().padLeft(2, '0')}:${exportedTime.minute.toString().padLeft(2, '0')}'),
              if (byCategory.isNotEmpty) ...[
                const SizedBox(height: S.xs),
                _SummaryRow(label: '分类分布', value: _formatDist(byCategory)),
              ],
              if (byPriority.isNotEmpty)
                _SummaryRow(label: '优先级分布', value: _formatDist(byPriority)),
              // 训练摘要合并到摘要卡
              if (export.trainingSummary.isNotEmpty) ...[
                const SizedBox(height: S.xs),
                for (final entry in export.trainingSummary.entries.take(4))
                  _SummaryRow(label: entry.key, value: '${entry.value}'),
              ],
            ],
          ),
        ),

        // 约束提示预览 (可折叠, 默认折叠)
        if (export.constraintPrompt.isNotEmpty) ...[
          const SizedBox(height: S.lg),
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: S.sm),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(R.sm),
              side: BorderSide(color: AppPalette.divider(b)),
            ),
            collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(R.sm),
              side: BorderSide(color: AppPalette.divider(b)),
            ),
            dense: true,
            title: Row(
              children: [
                Icon(Icons.psychology_outlined, size: 14, color: AppPalette.textSecondary(b)),
                const SizedBox(width: 6),
                Text('约束提示 (注入 AI 的 system prompt)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textSecondary(b))),
              ],
            ),
            subtitle: Text('${export.constraintPrompt.length} 字符',
                style: TextStyle(fontSize: 10, color: AppPalette.textTertiary(b))),
            children: [
              Padding(
                padding: const EdgeInsets.all(S.sm),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(S.sm),
                  decoration: BoxDecoration(
                    color: AppPalette.surfaceHigh(b),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppPalette.divider(b)),
                  ),
                  child: SelectableText(
                    export.constraintPrompt,
                    style: TextStyle(
                        fontSize: 11, fontFamily: 'monospace', height: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ],

        // 规则列表
        const SizedBox(height: S.lg),
        _SectionLabel(icon: Icons.list_alt_rounded, text: '规则列表 (${export.rules.length})'),
        const SizedBox(height: S.sm),
        for (final r in export.rules)
          Padding(
            padding: const EdgeInsets.only(bottom: S.xs),
            child: _RuleCard(rule: r),
          ),
      ],
    );
  }

  String _formatDist(Map<String, int> dist) {
    final sorted = dist.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => '${e.key}: ${e.value}').join('  ');
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: AppPalette.textTertiary(b),
                    fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppPalette.textSecondary(Theme.of(context).brightness)),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(Theme.of(context).brightness))),
      ],
    );
  }
}

class _RuleCard extends StatelessWidget {
  final TrainingRule rule;
  const _RuleCard({required this.rule});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final priorityColor = rule.priority == 'high'
        ? AppColors.error
        : rule.priority == 'medium'
            ? AppColors.warning
            : AppPalette.textTertiary(b);
    return AppCard(
      padding: const EdgeInsets.all(S.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 优先级标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: priorityColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: priorityColor.withValues(alpha: 0.4)),
            ),
            child: Text(rule.priority.toUpperCase(),
                style: TextStyle(
                    fontSize: 9, color: priorityColor, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: S.sm),
          // 分类
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(rule.category,
                style: TextStyle(
                    fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: S.sm),
          // 规则内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(rule.instruction,
                    style: const TextStyle(fontSize: 12, height: 1.4)),
                if (rule.source.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('${rule.source}  ·  ${rule.scope}',
                        style: TextStyle(
                            fontSize: 10, color: AppPalette.textTertiary(b))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
