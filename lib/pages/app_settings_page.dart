/// 书坊 ShuFang 应用设置页
///
/// 真正的应用设置 (区别于"设定集"页面):
/// - 外观: 主题模式 (日间/夜间/跟随系统) + 编辑器字体
/// - AI 模型: API 运营商配置入口 + 默认模型选择
/// - 关于: 版本信息 + 引擎状态 + 数据目录
///
/// 路由: AppRoute.settings (NavRail 设置图标)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/app_components.dart';
import '../store/companion_store.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';
import '../store/navigation_store.dart';
import '../store/preset_models.dart';
import '../theme/app_background.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../widgets/pixel_companion.dart';
import '../widgets/pixel_companion_settings.dart';
import 'api_providers_page.dart';
import 'training_panel_page.dart';

// ============================================================
// 字体候选
// ============================================================

const _fontOptions = <(String label, String? family)>[
  ('系统默认', null),
  ('宋体', 'serif'),
  ('黑体', 'sans-serif'),
  ('等宽', 'monospace'),
];

// ============================================================
// 应用设置页
// ============================================================

class AppSettingsPage extends ConsumerStatefulWidget {
  const AppSettingsPage({super.key});

  @override
  ConsumerState<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends ConsumerState<AppSettingsPage> {
  bool _engineReady = false;
  bool _checkingEngine = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await LocalDataSource.isEngineReachable();
    if (mounted) {
      setState(() {
        _engineReady = ok;
        _checkingEngine = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final themeMode = ref.watch(themeModeProvider);
    final font = ref.watch(editorFontFamilyProvider);
    final selectedModel = ref.watch(selectedModelProvider);

    return AppBackground(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed:
                () => ref.read(navigationControllerProvider.notifier).back(),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.xl, S.xxl),
          children: [
            // ========== 外观 ==========
            _SectionTitle(icon: Icons.palette_outlined, title: '外观'),
            const SizedBox(height: S.sm),
            AppCard(
              padding: const EdgeInsets.all(S.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 主题模式
                  const Text(
                    '主题模式',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: S.xs),
                  Wrap(
                    spacing: S.sm,
                    children: [
                      _ChoiceChip(
                        label: '日间',
                        icon: Icons.light_mode_outlined,
                        selected: themeMode == ThemeMode.light,
                        onTap:
                            () =>
                                ref.read(themeModeProvider.notifier).state =
                                    ThemeMode.light,
                      ),
                      _ChoiceChip(
                        label: '夜间',
                        icon: Icons.dark_mode_outlined,
                        selected: themeMode == ThemeMode.dark,
                        onTap:
                            () =>
                                ref.read(themeModeProvider.notifier).state =
                                    ThemeMode.dark,
                      ),
                      _ChoiceChip(
                        label: '跟随系统',
                        icon: Icons.brightness_auto_outlined,
                        selected: themeMode == ThemeMode.system,
                        onTap:
                            () =>
                                ref.read(themeModeProvider.notifier).state =
                                    ThemeMode.system,
                      ),
                    ],
                  ),
                  const Divider(height: S.xl),
                  // 编辑器字体
                  const Text(
                    '编辑器字体',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: S.xs),
                  Wrap(
                    spacing: S.sm,
                    children: [
                      for (final opt in _fontOptions)
                        _ChoiceChip(
                          label: opt.$1,
                          selected: font == opt.$2,
                          onTap:
                              () =>
                                  ref
                                      .read(editorFontFamilyProvider.notifier)
                                      .state = opt.$2,
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: S.xl),

            _SectionTitle(icon: Icons.auto_awesome_outlined, title: '写作伙伴'),
            const SizedBox(height: S.sm),
            AppCard(
              padding: const EdgeInsets.all(S.md),
              child: Row(
                children: [
                  PixelCompanionLive(
                    controller: ref.watch(companionControllerProvider),
                    size: 64,
                  ),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '像素助手',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        const Text('形象、动画与本地陪伴提示'),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed:
                                  () => showCompanionSettingsSheet(
                                    context,
                                    ref.read(companionControllerProvider),
                                  ),
                              child: const Text('设置伙伴'),
                            ),
                            TextButton(
                              onPressed:
                                  () => ref
                                      .read(
                                        navigationControllerProvider.notifier,
                                      )
                                      .push(AppRoute.companion),
                              child: const Text('动作预览'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: S.xl),

            // ========== AI 模型 ==========
            _SectionTitle(icon: Icons.smart_toy_outlined, title: 'AI 模型'),
            const SizedBox(height: S.sm),
            // D43: API 运营商配置入口 (替代旧的 API Key 输入框)
            AppCard(
              padding: const EdgeInsets.all(S.md),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ApiProvidersPage()),
                );
              },
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.hub_outlined,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'API 运营商配置',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '管理 DeepSeek / OpenAI / 通义千问 / 智谱 / 自定义 5 个运营商的 API Key、Base URL、默认模型, 测试连通性, 一键切换默认运营商。',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppPalette.textTertiary(b),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppPalette.textTertiary(b),
                  ),
                ],
              ),
            ),
            const SizedBox(height: S.sm),
            // 默认模型选择 (D46: 用前端预设列表, 不依赖引擎)
            AppCard(
              padding: const EdgeInsets.all(S.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '默认模型',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AI 功能使用的模型。内置国内主流厂商预设, 引擎未启动也可选择。模型按运营商分组, 自动按前缀路由 (deepseek-*/gpt-*/qwen-*/glm-*/moonshot-*/doubao-*/ernie-*)。',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppPalette.textTertiary(b),
                    ),
                  ),
                  const SizedBox(height: S.sm),
                  // D46: 预设模型下拉 (不依赖引擎, 离线可用)
                  DropdownButtonFormField<String>(
                    value:
                        _presetModelIds.contains(selectedModel)
                            ? selectedModel
                            : null,
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color:
                            _presetModelIds.contains(selectedModel)
                                ? AppColors.primary
                                : AppPalette.textTertiary(b),
                      ),
                      hintText:
                          _presetModelIds.contains(selectedModel)
                              ? null
                              : '当前: $selectedModel (自定义)',
                    ),
                    selectedItemBuilder:
                        (ctx) => _buildSelectedItem(selectedModel, b),
                    items: _buildPresetItems(b, selectedModel),
                    onChanged: (v) {
                      if (v != null) {
                        ref.read(selectedModelProvider.notifier).state = v;
                      }
                    },
                  ),
                  const SizedBox(height: S.xs),
                  // 手动输入模型 ID (自定义模型 / 私有部署模型)
                  Text(
                    '或手动输入模型 ID (自定义/私有部署)',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppPalette.textTertiary(b),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    initialValue: selectedModel,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'deepseek-v4-pro',
                      border: OutlineInputBorder(),
                    ),
                    onFieldSubmitted: (v) {
                      final trimmed = v.trim();
                      if (trimmed.isNotEmpty) {
                        ref.read(selectedModelProvider.notifier).state =
                            trimmed;
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: S.xl),

            // ========== 开发者 ==========
            _SectionTitle(icon: Icons.developer_mode_rounded, title: '开发者'),
            const SizedBox(height: S.sm),
            // D49: 训练面板入口 (读本地 training_rules.json, 不依赖引擎)
            AppCard(
              padding: const EdgeInsets.all(S.md),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TrainingPanelPage()),
                );
              },
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.model_training_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '训练面板',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '查看训练规则、约束提示、训练状态。本地副本不依赖引擎, 引擎在线时可同步刷新。',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppPalette.textTertiary(b),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppPalette.textTertiary(b),
                  ),
                ],
              ),
            ),

            const SizedBox(height: S.xl),

            // ========== 关于 ==========
            _SectionTitle(icon: Icons.info_outline, title: '关于'),
            const SizedBox(height: S.sm),
            AppCard(
              padding: const EdgeInsets.all(S.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AboutRow(label: '应用', value: '书坊 ShuFang'),
                  _AboutRow(label: '版本', value: '1.0.0'),
                  const Divider(height: S.lg),
                  _AboutRow(
                    label: '引擎状态',
                    value:
                        _checkingEngine
                            ? '检测中…'
                            : (_engineReady ? '已连接' : '未连接 (AI/单元集功能不可用)'),
                    valueColor:
                        _checkingEngine
                            ? null
                            : (_engineReady
                                ? AppColors.success
                                : AppColors.warning),
                  ),
                  _AboutRow(label: '数据目录', value: _storageRoot()),
                  const Divider(height: S.lg),
                  Text(
                    '写作 IDE — 本地优先, 零云端依赖。\n问题反馈请联系开发者。',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppPalette.textTertiary(b),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// D46: 预设模型 id 集合 (用于判断当前 selectedModel 是否在预设内)
  static final Set<String> _presetModelIds = {
    for (final pm in allPresetModels) pm.model.id,
  };

  /// D46: 预设模型下拉项 (按运营商分组, 不依赖引擎)
  List<DropdownMenuItem<String>> _buildPresetItems(
    Brightness b,
    String selected,
  ) {
    final items = <DropdownMenuItem<String>>[];
    for (final provider in kPresetProviders) {
      // 分组标题 (运营商名, 不可选)
      items.add(
        DropdownMenuItem<String>(
          enabled: false,
          value: '__group_${provider.id}',
          child: Text(
            provider.name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppPalette.textTertiary(b),
            ),
          ),
        ),
      );
      // 该运营商的模型
      for (final m in provider.models) {
        items.add(
          DropdownMenuItem<String>(
            value: m.id,
            child: Row(
              children: [
                Icon(
                  m.id == selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  size: 12,
                  color:
                      m.id == selected
                          ? AppColors.primary
                          : AppPalette.textTertiary(b),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        m.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (m.description.isNotEmpty)
                        Text(
                          m.description,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppPalette.textTertiary(b),
                          ),
                        ),
                    ],
                  ),
                ),
                if (m.speed.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: _SpeedChip(speed: m.speed),
                  ),
              ],
            ),
          ),
        );
      }
    }
    return items;
  }

  /// D46: 选中项展示 (当前模型不在预设内时显示自定义标签)
  List<Widget> _buildSelectedItem(String selected, Brightness b) {
    // 在预设内 → 显示模型名
    for (final pm in allPresetModels) {
      if (pm.model.id == selected) {
        return [Text(pm.model.name, style: const TextStyle(fontSize: 13))];
      }
    }
    // 不在预设内 → 显示自定义模型 id
    return [
      Icon(Icons.edit_rounded, size: 12, color: AppPalette.textTertiary(b)),
      const SizedBox(width: 4),
      Text(
        selected,
        style: TextStyle(fontSize: 13, color: AppPalette.textSecondary(b)),
      ),
    ];
  }

  String _storageRoot() {
    return const String.fromEnvironment(
      'HERMES_STORAGE_ROOT',
      defaultValue: 'D:\\Hermes\\shufang_storage',
    );
  }
}

// ============================================================
// 子组件
// ============================================================

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: S.xs),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceChip({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              selected
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppPalette.surface(b),
          border: Border.all(
            color: selected ? AppColors.primary : AppPalette.divider(b),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color:
                    selected ? AppColors.primary : AppPalette.textSecondary(b),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color:
                    selected ? AppColors.primary : AppPalette.textSecondary(b),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  final String speed;
  const _SpeedChip({required this.speed});

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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        speed,
        style: TextStyle(fontSize: 9, color: c, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _AboutRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: AppPalette.textTertiary(b)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: valueColor ?? AppPalette.textPrimary(b),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
