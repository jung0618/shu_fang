/// AI 助手面板 (D40: 单一聊天入口 + 模型切换 + 上下文策略)
///
/// 设计变更 (D40):
/// - 删除 4 外置按键 (续写/建议/总结/改写) — 与 chat 的斜杠命令重复
/// - 永远只显示 AiChatPanel, 不再切换 quickActions/chat 模式
/// - 顶部加模型下拉 (持久化到 UserPrefs.selectedModel)
/// - 顶部加上下文策略切换 (compact 4k / balanced 8k / detailed 16k, 持久化)
/// - 斜杠命令 chips 移到 AiChatPanel 输入框上方
///
/// D44 增量:
/// - 顶部加运营商快速切换 (一键切默认 provider, 后端持久化)
/// - 顶部加齿轮配置入口 (随时跳转 API 运营商配置页, 无需进设置)
///
/// 业界案例参考 (Cursor / Claude / ChatGPT / Copilot Chat):
/// - 单一聊天框 + 斜杠命令 + 模型顶部下拉 + 上下文预览
/// - 4 个独立按键卡片是反模式 (功能与聊天内 /续写 /改写 /总结 /建议 重复)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../pages/api_providers_page.dart';
import '../store/editor_store.dart';
import '../theme/colors.dart';
import '../theme/radius.dart';
import '../theme/spacing.dart';
import 'ai_chat_panel.dart';

class AiContextPanel extends ConsumerWidget {
  const AiContextPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppPalette.surface(Theme.of(context).brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelHeader(),
          const Divider(height: 1),
          // D40: 永远只显示聊天面板 (4 外置按键已删除)
          const Expanded(child: AiChatPanel()),
        ],
      ),
    );
  }
}

/// 面板顶部 — 标题 + 运营商切换 + 模型下拉 + 上下文策略 + 配置入口 + 关闭按钮
class _PanelHeader extends ConsumerWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedModel = ref.watch(selectedModelProvider);
    final strategy = ref.watch(aiContextStrategyProvider);
    final modelsAsync = ref.watch(modelsProvider);
    // D44: 监听运营商列表 (用于顶部快速切换 + 状态显示)
    final providersAsync = ref.watch(llmProvidersProvider);

    // D52: 两行布局 — 第一行标题+操作按钮, 第二行配置控件
    // 解决 320px 宽度内单行 Row 溢出导致右侧内容被裁切的问题
    return Container(
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.sm, S.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行: 图标 + 标题 + Spacer + 配置入口 + 关闭按钮
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      AppColors.aiGradientStart,
                      AppColors.aiGradientEnd,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: S.sm),
              Text('AI 助手', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              // D44: 配置入口 (齿轮图标, 随时跳转 API 运营商配置页)
              IconButton(
                icon: const Icon(Icons.tune_rounded, size: 16),
                tooltip: 'API 运营商配置',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ApiProvidersPage()),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: '关闭 AI 面板 (Ctrl+J)',
                visualDensity: VisualDensity.compact,
                onPressed:
                    () =>
                        ref.read(aiPanelExpandedProvider.notifier).state =
                            false,
              ),
            ],
          ),
          const SizedBox(height: S.xs),
          // 第二行: 运营商切换 + 上下文策略 + 模型下拉。
          // 用 Wrap 处理窄面板和系统字体放大，避免设置控件横向溢出。
          Wrap(
            spacing: S.xs,
            runSpacing: S.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // D44: 运营商快速切换 — 一键切默认 provider (后端持久化)
              providersAsync.when(
                data:
                    (resp) => _ProviderSwitcher(
                      resp: resp,
                      onSwitch: (provider) async {
                        try {
                          await ref
                              .read(llmProvidersProvider.notifier)
                              .switchDefault(provider);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '默认运营商已切换: ${_providerShortName(provider)}',
                              ),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('切换失败: $e'),
                              duration: const Duration(seconds: 3),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                loading:
                    () => const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                error: (_, __) => const SizedBox.shrink(),
              ),
              // D40: 上下文策略切换 (紧凑/均衡/详尽)
              _StrategySwitcher(
                strategy: strategy,
                onChanged: (s) {
                  if (s == strategy) return;
                  ref.read(aiContextStrategyProvider.notifier).state = s;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('上下文策略: ${s.label} (${s.desc})'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              // D40: 模型下拉 (持久化) — 限制最大宽度，避免长模型名撑破面板。
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: modelsAsync.when(
                  data:
                      (models) => _ModelDropdown(
                        models: models,
                        selectedModel: selectedModel,
                        onChanged: (m) {
                          if (m == selectedModel) return;
                          ref.read(selectedModelProvider.notifier).state = m;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('模型已切换: $m'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                  loading:
                      () => const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  error:
                      (_, __) => _ModelDropdown(
                        models: const [],
                        selectedModel: selectedModel,
                        onChanged:
                            (m) =>
                                ref.read(selectedModelProvider.notifier).state =
                                    m,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// D44: 运营商短名 (用于顶部紧凑显示 + SnackBar 提示)
String _providerShortName(String provider) {
  switch (provider) {
    case 'deepseek':
      return 'DeepSeek';
    case 'openai':
      return 'OpenAI';
    case 'qwen':
      return '通义千问';
    case 'zhipu':
      return '智谱 GLM';
    case 'custom':
      return '自定义';
    default:
      return provider;
  }
}

/// D44: 运营商快速切换 — 紧凑下拉, 一键切默认 provider
/// 绿色圆点 = 已配置, 灰色 = 未配置; 当前默认带勾选
class _ProviderSwitcher extends StatelessWidget {
  final LlmProvidersResponse resp;
  final ValueChanged<String> onSwitch;
  const _ProviderSwitcher({required this.resp, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final current = resp.currentProvider;
    final currentInfo = resp.providers.firstWhere(
      (p) => p.id == current,
      orElse:
          () =>
              resp.providers.isNotEmpty
                  ? resp.providers.first
                  : const LlmProviderInfo(id: '', name: ''),
    );
    final shortName = _providerShortName(current);

    return PopupMenuButton<String>(
      tooltip: '切换运营商 (当前: $shortName)',
      onSelected: onSwitch,
      itemBuilder: (ctx) => _buildItems(b, current),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: AppPalette.surfaceHigh(b),
          borderRadius: BorderRadius.circular(R.xs),
          border: Border.all(color: AppPalette.divider(b)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 状态点: 已配置=绿, 未配置=黄
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color:
                    currentInfo.configured
                        ? AppColors.success
                        : AppColors.warning,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              shortName,
              style: TextStyle(
                fontSize: 11,
                color: AppPalette.textSecondary(b),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: AppPalette.textTertiary(b),
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildItems(Brightness b, String current) {
    final items = <PopupMenuEntry<String>>[];
    items.add(
      PopupMenuItem<String>(
        enabled: false,
        height: 28,
        child: Text(
          '切换运营商',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppPalette.textTertiary(b),
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
    for (final p in resp.providers) {
      final isCurrent = p.id == current;
      items.add(
        PopupMenuItem<String>(
          value: p.id,
          height: 36,
          child: Row(
            children: [
              // 状态点
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: p.configured ? AppColors.success : AppColors.warning,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                isCurrent
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                size: 14,
                color: isCurrent ? AppColors.ai : AppPalette.textTertiary(b),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.name, style: const TextStyle(fontSize: 12)),
                    if (!p.configured)
                      Text(
                        '未配置 Key',
                        style: TextStyle(fontSize: 9, color: AppColors.warning),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    items.add(const PopupMenuDivider());
    items.add(
      PopupMenuItem<String>(
        enabled: false,
        height: 28,
        child: Text(
          '点齿轮进入完整配置',
          style: TextStyle(
            fontSize: 9,
            color: AppPalette.textTertiary(b),
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
    return items;
  }
}

/// 模型下拉 — 紧凑型, 显示当前模型名, 点击弹菜单
/// D43: 按 provider 分组, 每组带分组标题 (与 AppSettingsPage 一致)
class _ModelDropdown extends StatelessWidget {
  final List<ModelInfo> models;
  final String selectedModel;
  final ValueChanged<String> onChanged;
  const _ModelDropdown({
    required this.models,
    required this.selectedModel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    // 找当前模型显示名 (找不到则用 ID)
    final current = models.firstWhere(
      (m) => m.id == selectedModel,
      orElse: () => ModelInfo(id: selectedModel, name: selectedModel),
    );
    final currentName = current.name;
    // 紧凑显示: 截断到 12 字符
    final display =
        currentName.length > 12
            ? '${currentName.substring(0, 12)}…'
            : currentName;
    return PopupMenuButton<String>(
      tooltip: '切换模型',
      onSelected: onChanged,
      itemBuilder: (ctx) => _buildItems(b),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.ai.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(R.xs),
          border: Border.all(color: AppColors.ai.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.memory, size: 12, color: AppColors.ai),
            const SizedBox(width: 4),
            // D52: Flexible + ellipsis 防止模型名过长导致溢出
            Flexible(
              child: Text(
                display,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.ai,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 14, color: AppColors.ai),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildItems(Brightness b) {
    if (models.isEmpty) {
      return [
        PopupMenuItem(
          enabled: false,
          child: Text(
            '引擎未启动, 当前: $selectedModel',
            style: TextStyle(fontSize: 11, color: AppPalette.textTertiary(b)),
          ),
        ),
      ];
    }

    // 按 provider 分组
    final groups = <String, List<ModelInfo>>{};
    for (final m in models) {
      final g = m.provider.isEmpty ? 'other' : m.provider;
      groups.putIfAbsent(g, () => []).add(m);
    }
    const order = ['deepseek', 'openai', 'qwen', 'zhipu', 'custom', 'other'];
    final sortedKeys =
        groups.keys.toList()..sort((a, b) {
          final ia = order.indexOf(a);
          final ib = order.indexOf(b);
          return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
        });

    final items = <PopupMenuEntry<String>>[];
    for (final key in sortedKeys) {
      // 分组标题 (不可选)
      items.add(
        PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text(
            _providerGroupName(key),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppPalette.textTertiary(b),
              letterSpacing: 0.4,
            ),
          ),
        ),
      );
      // 该组模型
      for (final m in groups[key]!) {
        items.add(
          PopupMenuItem<String>(
            value: m.id,
            height: 36,
            child: Row(
              children: [
                Icon(
                  m.id == selectedModel
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  size: 14,
                  color:
                      m.id == selectedModel
                          ? AppColors.ai
                          : AppPalette.textTertiary(b),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(m.name, style: const TextStyle(fontSize: 12)),
                      if (m.description.isNotEmpty)
                        Text(
                          m.description,
                          style: TextStyle(
                            fontSize: 9,
                            color: AppPalette.textTertiary(b),
                          ),
                        ),
                    ],
                  ),
                ),
                if (m.speed.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: _SpeedTag(speed: m.speed),
                  ),
              ],
            ),
          ),
        );
      }
    }
    return items;
  }

  String _providerGroupName(String key) {
    switch (key) {
      case 'deepseek':
        return 'DeepSeek';
      case 'openai':
        return 'OpenAI';
      case 'qwen':
        return '通义千问';
      case 'zhipu':
        return '智谱 GLM';
      case 'custom':
        return '自定义';
      default:
        return '其他';
    }
  }
}

/// 模型速度标签 (紧凑型, 用于 AI 面板顶部下拉)
class _SpeedTag extends StatelessWidget {
  final String speed;
  const _SpeedTag({required this.speed});

  @override
  Widget build(BuildContext context) {
    Color c;
    if (speed.contains('快')) {
      c = AppColors.success;
    } else if (speed.contains('慢')) {
      c = AppColors.warning;
    } else {
      c = AppPalette.textTertiary(Theme.of(context).brightness);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        speed,
        style: TextStyle(fontSize: 9, color: c, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// 上下文策略切换 — 紧凑型, 点击弹菜单
class _StrategySwitcher extends StatelessWidget {
  final AiContextStrategy strategy;
  final ValueChanged<AiContextStrategy> onChanged;
  const _StrategySwitcher({required this.strategy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return PopupMenuButton<AiContextStrategy>(
      tooltip: '上下文策略: ${strategy.label} (${strategy.desc})',
      onSelected: onChanged,
      itemBuilder:
          (ctx) => [
            for (final s in AiContextStrategy.values)
              PopupMenuItem<AiContextStrategy>(
                value: s,
                child: Row(
                  children: [
                    Icon(
                      s == strategy
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color:
                          s == strategy
                              ? AppColors.ai
                              : AppPalette.textTertiary(b),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            s.label,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            s.desc,
                            style: TextStyle(
                              fontSize: 10,
                              color: AppPalette.textTertiary(b),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppPalette.surfaceHigh(b),
          borderRadius: BorderRadius.circular(R.xs),
          border: Border.all(color: AppPalette.divider(b)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 12,
              color: AppPalette.textSecondary(b),
            ),
            const SizedBox(width: 4),
            Text(
              strategy.label,
              style: TextStyle(
                fontSize: 11,
                color: AppPalette.textSecondary(b),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: AppPalette.textTertiary(b),
            ),
          ],
        ),
      ),
    );
  }
}
