/// D43: 专业 API 运营商切换界面
/// D46: 引擎离线时用预设列表 + 本地 Prefs 展示, 不报"接口不可用"
///
/// 业界工业实践 (Cursor / LobeChat / OpenWebUI / Cherry Studio):
/// - 运营商列表 + 状态徽章 (默认/已配置/未配置)
/// - 单卡展开编辑 (API Key + Base URL + 默认模型)
/// - 连通性测试 (延迟 ms + 错误信息)
/// - 一键设为默认 + 清除配置
/// - D46: 离线可配置 (Key 存本地 Prefs, 引擎启动后自动同步)
///
/// 路由: Navigator.push (从 AppSettingsPage 进入, 不污染 AppRoute 枚举)
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../components/app_components.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';
import '../store/local_prefs.dart';
import '../store/preset_models.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';

// ============================================================
// Provider: 运营商详情列表 (可刷新)
// ============================================================

final llmProvidersProvider = StateNotifierProvider<
  LlmProvidersNotifier,
  AsyncValue<LlmProvidersResponse>
>((ref) {
  ref.watch(storageRootProvider);
  return LlmProvidersNotifier();
});

class LlmProvidersNotifier
    extends StateNotifier<AsyncValue<LlmProvidersResponse>> {
  LlmProvidersNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final revision = localDataSource.sessionRevision;
    state = const AsyncValue.loading();
    try {
      final resp = await apiClient.getLlmProviders();
      if (!mounted || revision != localDataSource.sessionRevision) return;
      state = AsyncValue.data(resp);
      // 同步当前默认运营商到本地 Prefs (UI 状态恢复用)
      await PrefsController.update(
        PrefsController.current.copyWith(currentProvider: resp.currentProvider),
      );
    } catch (_) {
      // D46: 引擎未启动 → 用预设列表 + 本地 Prefs 构造离线 response
      if (!mounted || revision != localDataSource.sessionRevision) return;
      final offlineResp = _buildOfflineResponse();
      state = AsyncValue.data(offlineResp);
    }
  }

  Future<void> refresh() => _load();

  /// D46: 引擎离线时, 从预设列表 + 本地 Prefs 构造离线 response
  LlmProvidersResponse _buildOfflineResponse() {
    final prefs = PrefsController.current;
    final currentProvider = prefs.currentProvider;
    final localProviders =
        prefs
            .apiProviders; // {deepseek: {api_key_masked, base_url, default_model}}

    final providers = <LlmProviderInfo>[];
    for (final preset in kPresetProviders) {
      final local = localProviders[preset.id] as Map<String, dynamic>? ?? {};
      final maskedKey = local['api_key_masked'] as String? ?? '';
      final baseUrl = local['base_url'] as String? ?? '';
      final defaultModel =
          (local['default_model'] as String?) ??
          (preset.models.isNotEmpty ? preset.models.first.id : '');

      providers.add(
        LlmProviderInfo(
          id: preset.id,
          name: preset.name,
          configured: maskedKey.isNotEmpty,
          isDefault: preset.id == currentProvider,
          apiKeyMasked: maskedKey,
          baseUrl: baseUrl,
          baseUrlDefault: preset.baseUrlDefault,
          defaultModel: defaultModel,
          models:
              preset.models
                  .map(
                    (m) => LlmModelInfo(
                      id: m.id,
                      name: m.name,
                      speed: m.speed,
                      description: m.description,
                    ),
                  )
                  .toList(),
        ),
      );
    }

    return LlmProvidersResponse(
      currentProvider: currentProvider,
      availableProviders: kPresetProviders.map((p) => p.id).toList(),
      providers: providers,
    );
  }

  /// 保存配置后刷新 (D46: 离线时只存本地, 在线时同步后端)
  ///
  /// D48: 同时存明文 api_key_plain 到本地 Prefs (仅用于直连 LLM, 不上传引擎).
  /// - apiKey 非空: 更新 masked + plain
  /// - apiKey 为空 (D45 留空保留原值): 保留原有 masked + plain
  Future<void> saveAndRefresh({
    required String provider,
    required String apiKey,
    String baseUrl = '',
    String defaultModel = '',
  }) async {
    final revision = localDataSource.sessionRevision;
    // 1. 先存本地 Prefs (无论引擎是否在线, 本地都存一份)
    final prefs = PrefsController.current;
    final newProviders = Map<String, dynamic>.from(prefs.apiProviders);
    final existing = newProviders[provider] as Map<String, dynamic>? ?? {};
    newProviders[provider] = {
      // apiKey 非空 → 更新 masked + plain; 为空 → 保留原值 (留空保留原值语义)
      if (apiKey.isNotEmpty) ...{
        'api_key_masked': _maskKey(apiKey),
        'api_key_plain': apiKey,
      } else ...{
        if (existing['api_key_masked'] != null)
          'api_key_masked': existing['api_key_masked'],
        if (existing['api_key_plain'] != null)
          'api_key_plain': existing['api_key_plain'],
      },
      'base_url': baseUrl,
      'default_model': defaultModel,
    };
    await PrefsController.update(prefs.copyWith(apiProviders: newProviders));
    if (!mounted || revision != localDataSource.sessionRevision) return;

    // 2. 尝试同步到后端 (失败不阻塞, 引擎启动后会自动同步)
    try {
      await apiClient.saveLlmConfig(
        provider: provider,
        apiKey: apiKey,
        baseUrl: baseUrl,
        defaultModel: defaultModel,
      );
    } catch (_) {
      // 引擎离线, 静默忽略 (已存本地)
    }

    // 3. 刷新 UI (用离线 response 或在线 response)
    await _load();
  }

  /// 切换默认运营商 (D46: 离线时只存本地, 在线时同步后端)
  Future<void> switchDefault(String provider) async {
    final revision = localDataSource.sessionRevision;
    await PrefsController.update(
      PrefsController.current.copyWith(currentProvider: provider),
    );
    if (!mounted || revision != localDataSource.sessionRevision) return;
    try {
      await apiClient.switchLlmProvider(provider);
    } catch (_) {
      // 引擎离线, 静默忽略
    }
    await _load();
  }

  /// 清除某运营商运行时配置 (D46: 离线时只清本地)
  Future<void> clear(String provider) async {
    final revision = localDataSource.sessionRevision;
    // 1. 清本地
    final prefs = PrefsController.current;
    final newProviders = Map<String, dynamic>.from(prefs.apiProviders);
    newProviders.remove(provider);
    await PrefsController.update(prefs.copyWith(apiProviders: newProviders));
    if (!mounted || revision != localDataSource.sessionRevision) return;
    // 2. 尝试同步后端
    try {
      await apiClient.clearLlmConfig(provider);
    } catch (_) {
      // 引擎离线, 静默忽略
    }
    await _load();
  }

  String _maskKey(String key) {
    if (key.length < 8) return '***';
    return '${key.substring(0, 6)}...${key.substring(key.length - 4)}';
  }
}

// ============================================================
// 页面
// ============================================================

class ApiProvidersPage extends ConsumerWidget {
  const ApiProvidersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(llmProvidersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('API 运营商配置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
            onPressed: () => ref.read(llmProvidersProvider.notifier).refresh(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (e, _) => _ErrorView(
              error: e.toString(),
              onRetry: () => ref.read(llmProvidersProvider.notifier).refresh(),
            ),
        data: (resp) => _ProvidersList(resp: resp),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(S.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.warning),
            const SizedBox(height: S.md),
            Text('引擎未启动或接口不可用', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: S.xs),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppPalette.textTertiary(Theme.of(context).brightness),
              ),
            ),
            const SizedBox(height: S.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProvidersList extends ConsumerStatefulWidget {
  final LlmProvidersResponse resp;
  const _ProvidersList({required this.resp});

  @override
  ConsumerState<_ProvidersList> createState() => _ProvidersListState();
}

class _ProvidersListState extends ConsumerState<_ProvidersList> {
  String? _expandedProvider;

  @override
  void initState() {
    super.initState();
    // 默认展开当前默认运营商
    _expandedProvider = widget.resp.currentProvider;
  }

  @override
  void didUpdateWidget(covariant _ProvidersList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_expandedProvider == null ||
        !widget.resp.providers.any((p) => p.id == _expandedProvider)) {
      _expandedProvider = widget.resp.currentProvider;
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final current = widget.resp.currentProvider;
    final available = widget.resp.availableProviders;
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.xl, S.xxl),
      children: [
        // 顶部状态条
        AppCard(
          padding: const EdgeInsets.all(S.md),
          color: AppColors.primary.withValues(alpha: 0.06),
          child: Row(
            children: [
              Icon(Icons.hub_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: S.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '当前默认运营商',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppPalette.textTertiary(b),
                      ),
                    ),
                    Text(
                      _providerName(widget.resp.providers, current),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: S.md),
              if (available.isEmpty)
                _Badge(text: '未配置', color: AppColors.warning)
              else
                _Badge(
                  text: '已配置 ${available.length} 个',
                  color: AppColors.success,
                ),
            ],
          ),
        ),
        const SizedBox(height: S.lg),
        // 提示
        Text(
          '配置存本地 + 引擎同步 (引擎启动后自动同步到后端, 重启保留)。点击卡片展开查看 / 修改。引擎未启动时也可配置, 启动后自动生效。',
          style: TextStyle(fontSize: 11, color: AppPalette.textTertiary(b)),
        ),
        const SizedBox(height: S.lg),
        // 运营商卡片
        for (final p in widget.resp.providers)
          Padding(
            padding: const EdgeInsets.only(bottom: S.md),
            child: _ProviderCard(
              provider: p,
              expanded: _expandedProvider == p.id,
              onToggle: () {
                setState(() {
                  _expandedProvider = _expandedProvider == p.id ? null : p.id;
                });
              },
            ),
          ),
      ],
    );
  }

  String _providerName(List<LlmProviderInfo> list, String id) {
    for (final p in list) {
      if (p.id == id) return p.name;
    }
    return id;
  }
}

class _ProviderCard extends ConsumerStatefulWidget {
  final LlmProviderInfo provider;
  final bool expanded;
  final VoidCallback onToggle;
  const _ProviderCard({
    required this.provider,
    required this.expanded,
    required this.onToggle,
  });

  @override
  ConsumerState<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends ConsumerState<_ProviderCard> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _modelCtrl;
  bool _keyVisible = false;
  bool _testing = false;
  bool _saving = false;
  LlmTestResult? _testResult;
  // D45: 编辑模式 (查看模式 = 显示 masked key + Edit 按钮; 编辑模式 = 输入新 Key)
  // 已配置 provider 默认查看模式; 未配置 provider 默认编辑模式 (用户必须输入)
  late bool _editing;

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _keyCtrl = TextEditingController();
    _urlCtrl = TextEditingController(
      text: p.baseUrl.isEmpty ? p.baseUrlDefault : p.baseUrl,
    );
    _modelCtrl = TextEditingController(text: p.defaultModel);
    _editing = !p.configured; // 未配置 → 直接进编辑模式
  }

  @override
  void didUpdateWidget(covariant _ProviderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 刷新后, 若用户没在编辑, 同步最新值
    if (oldWidget.provider.baseUrl != widget.provider.baseUrl ||
        oldWidget.provider.defaultModel != widget.provider.defaultModel) {
      if (_urlCtrl.text.isEmpty ||
          _urlCtrl.text == oldWidget.provider.baseUrlDefault ||
          _urlCtrl.text == oldWidget.provider.baseUrl) {
        _urlCtrl.text =
            widget.provider.baseUrl.isEmpty
                ? widget.provider.baseUrlDefault
                : widget.provider.baseUrl;
      }
      if (_modelCtrl.text.isEmpty ||
          _modelCtrl.text == oldWidget.provider.defaultModel) {
        _modelCtrl.text = widget.provider.defaultModel;
      }
    }
    // 配置状态变化时同步编辑模式 (例如清除后切到编辑模式)
    if (oldWidget.provider.configured && !widget.provider.configured) {
      _editing = true;
    }
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _urlCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _enterEditMode() {
    setState(() {
      _editing = true;
      _keyCtrl.clear(); // 进编辑模式清空, 等待输入新 Key
      _testResult = null;
    });
  }

  void _exitEditMode() {
    setState(() {
      _editing = false;
      _keyCtrl.clear();
      _testResult = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final p = widget.provider;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头部 (点击展开/折叠)
          InkWell(
            onTap: widget.onToggle,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(S.md, S.md, S.sm, S.md),
              child: Row(
                children: [
                  _ProviderIcon(providerId: p.id, size: 28),
                  const SizedBox(width: S.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (p.isDefault)
                              _Badge(text: '默认', color: AppColors.primary),
                            const SizedBox(width: 4),
                            if (p.configured)
                              _Badge(text: '已配置', color: AppColors.success)
                            else
                              _Badge(
                                text: '未配置',
                                color: AppPalette.textTertiary(b),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.apiKeyMasked.isNotEmpty
                              ? 'Key: ${p.apiKeyMasked}'
                              : '无 API Key',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppPalette.textTertiary(b),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    widget.expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppPalette.textSecondary(b),
                  ),
                ],
              ),
            ),
          ),
          // 展开内容
          if (widget.expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(S.md),
              child: _editing ? _buildEditMode(b, p) : _buildViewMode(b, p),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // D45: 查看模式 — 显示当前 masked Key + 切换默认/修改/清除/测试
  // ============================================================
  Widget _buildViewMode(Brightness b, LlmProviderInfo p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 当前配置信息块
        Container(
          padding: const EdgeInsets.all(S.sm),
          decoration: BoxDecoration(
            color: AppPalette.surfaceHigh(b),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppPalette.divider(b)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                label: '当前 API Key',
                value: p.apiKeyMasked.isNotEmpty ? p.apiKeyMasked : '(未配置)',
              ),
              const SizedBox(height: 4),
              _InfoRow(
                label: 'Base URL',
                value: p.baseUrl.isEmpty ? p.baseUrlDefault : p.baseUrl,
              ),
              const SizedBox(height: 4),
              _InfoRow(label: '默认模型', value: p.defaultModel),
            ],
          ),
        ),
        const SizedBox(height: S.md),
        // 操作行
        Wrap(
          spacing: S.sm,
          runSpacing: S.xs,
          children: [
            FilledButton.icon(
              onPressed: _enterEditMode,
              icon: const Icon(Icons.edit_rounded, size: 14),
              label: const Text('修改 API Key'),
            ),
            OutlinedButton.icon(
              onPressed: _testing ? null : () => _onTest(useExisting: true),
              icon:
                  _testing
                      ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.network_check_rounded, size: 14),
              label: const Text('测试连通性'),
            ),
            if (!p.isDefault)
              TextButton.icon(
                onPressed: () => _onSwitchDefault(p.id),
                icon: const Icon(Icons.star_rounded, size: 14),
                label: const Text('设为默认'),
              ),
            TextButton.icon(
              onPressed: () => _onClear(p.id),
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 14,
                color: AppColors.error,
              ),
              label: Text('清除', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
        if (_testResult != null) ...[
          const SizedBox(height: S.md),
          _TestResultView(result: _testResult!),
        ],
      ],
    );
  }

  // ============================================================
  // D45: 编辑模式 — 输入新 API Key + Base URL + 模型 + 保存/取消
  // ============================================================
  Widget _buildEditMode(Brightness b, LlmProviderInfo p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 提示行
        if (p.configured) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppColors.info.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppColors.info,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '当前 Key: ${p.apiKeyMasked}  →  输入新 Key 覆盖, 留空保存则保留原值',
                    style: TextStyle(fontSize: 11, color: AppColors.info),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: S.md),
        ],
        // API Key
        _FieldLabel(label: '新 API Key', hint: p.configured ? '留空保留原值' : '必填'),
        const SizedBox(height: 4),
        TextField(
          controller: _keyCtrl,
          obscureText: !_keyVisible,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: p.configured ? '(留空保留原值)' : 'sk-...',
            suffixIcon: IconButton(
              icon: Icon(
                _keyVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _keyVisible = !_keyVisible),
              tooltip: _keyVisible ? '隐藏' : '显示',
            ),
          ),
        ),
        const SizedBox(height: S.md),
        // Base URL
        _FieldLabel(label: 'Base URL', hint: 'OpenAI 兼容 API 地址'),
        const SizedBox(height: 4),
        TextField(
          controller: _urlCtrl,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText:
                p.baseUrlDefault.isEmpty
                    ? 'https://api.example.com/v1'
                    : p.baseUrlDefault,
          ),
        ),
        const SizedBox(height: S.md),
        // 默认模型
        _FieldLabel(label: '默认模型', hint: '该运营商推荐模型'),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _modelCtrl,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'model-id',
                ),
              ),
            ),
            if (p.models.isNotEmpty) ...[
              const SizedBox(width: S.xs),
              PopupMenuButton<String>(
                tooltip: '选择推荐模型',
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (v) => _modelCtrl.text = v,
                itemBuilder:
                    (_) => [
                      for (final m in p.models)
                        PopupMenuItem(
                          value: m.id,
                          child: Row(
                            children: [
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
                                  padding: const EdgeInsets.only(left: 6),
                                  child: _SpeedChip(speed: m.speed),
                                ),
                            ],
                          ),
                        ),
                    ],
              ),
            ],
          ],
        ),
        const SizedBox(height: S.md),
        // 操作行
        Wrap(
          spacing: S.sm,
          runSpacing: S.xs,
          children: [
            FilledButton.icon(
              onPressed: _saving ? null : _onSave,
              icon:
                  _saving
                      ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.save_outlined, size: 14),
              label: const Text('保存'),
            ),
            OutlinedButton.icon(
              onPressed: _testing ? null : _onTest,
              icon:
                  _testing
                      ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.network_check_rounded, size: 14),
              label: const Text('测试新配置'),
            ),
            if (p.configured)
              TextButton.icon(
                onPressed: _exitEditMode,
                icon: const Icon(Icons.close_rounded, size: 14),
                label: const Text('取消'),
              ),
          ],
        ),
        if (_testResult != null) ...[
          const SizedBox(height: S.md),
          _TestResultView(result: _testResult!),
        ],
      ],
    );
  }

  /// 测试连通性 (查看模式传 useExisting=true 用后端已保存的配置, 编辑模式传 false 用输入框的值)
  /// D51: 引擎离线时走直连测试 (DirectLlmClient), 不依赖后端 HTTP
  Future<void> _onTest({bool useExisting = false}) async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      // D51: 先尝试后端测试 (引擎在线时)
      final result = await apiClient.testLlmProvider(
        provider: widget.provider.id,
        apiKey: useExisting ? '' : _keyCtrl.text.trim(),
        baseUrl: useExisting ? '' : _urlCtrl.text.trim(),
        model: useExisting ? '' : _modelCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _testResult = result);
    } catch (e) {
      // D51: 引擎离线 → 走直连测试
      if (!mounted) return;
      await _onTestDirect(
        useExisting: useExisting,
        fallbackError: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// D51: 直连测试 — 引擎离线时直接从 Flutter 端发最小请求
  Future<void> _onTestDirect({
    required bool useExisting,
    required String fallbackError,
  }) async {
    final p = widget.provider;
    // 获取测试用 key: 编辑模式用输入框的值, 查看模式用本地存储的 plain key
    String apiKey;
    if (useExisting) {
      final prefs = PrefsController.current;
      final local = (prefs.apiProviders[p.id] as Map<String, dynamic>?) ?? {};
      apiKey = local['api_key_plain'] as String? ?? '';
    } else {
      apiKey = _keyCtrl.text.trim();
      // 留空时保留原 key
      if (apiKey.isEmpty) {
        final prefs = PrefsController.current;
        final local = (prefs.apiProviders[p.id] as Map<String, dynamic>?) ?? {};
        apiKey = local['api_key_plain'] as String? ?? '';
      }
    }
    if (apiKey.isEmpty) {
      setState(
        () =>
            _testResult = LlmTestResult(
              ok: false,
              error: '未配置 API Key (引擎离线, 无法用后端测试)',
            ),
      );
      return;
    }
    final baseUrl =
        _urlCtrl.text.trim().isEmpty
            ? (p.baseUrl.isEmpty ? p.baseUrlDefault : p.baseUrl)
            : _urlCtrl.text.trim();
    final model =
        _modelCtrl.text.trim().isEmpty
            ? p.defaultModel
            : _modelCtrl.text.trim();

    // D51: 直接用 HttpClient 发最小请求 (不走 DirectLlmClient, 因为要测试指定 provider)
    final url =
        baseUrl.endsWith('/')
            ? '${baseUrl.substring(0, baseUrl.length - 1)}/chat/completions'
            : '$baseUrl/chat/completions';
    final stopwatch = Stopwatch()..start();
    try {
      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 15);
      final request = await httpClient.postUrl(Uri.parse(url));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Authorization', 'Bearer $apiKey');
      request.write(
        jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
          'max_tokens': 1,
          'stream': false,
        }),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      stopwatch.stop();
      httpClient.close();
      if (response.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        final preview =
            choices != null && choices.isNotEmpty
                ? ((choices[0] as Map)['message']?['content'] ?? '').toString()
                : '';
        setState(
          () =>
              _testResult = LlmTestResult(
                ok: true,
                latencyMs: stopwatch.elapsedMilliseconds,
                responsePreview:
                    preview.length > 80 ? preview.substring(0, 80) : preview,
              ),
        );
      } else {
        setState(
          () =>
              _testResult = LlmTestResult(
                ok: false,
                latencyMs: stopwatch.elapsedMilliseconds,
                error:
                    'HTTP ${response.statusCode}: ${body.length > 200 ? '${body.substring(0, 200)}...' : body}',
              ),
        );
      }
    } catch (e) {
      stopwatch.stop();
      setState(
        () =>
            _testResult = LlmTestResult(
              ok: false,
              latencyMs: stopwatch.elapsedMilliseconds,
              error: '直连测试失败 (引擎离线): $e',
            ),
      );
    }
  }

  Future<void> _onSave() async {
    setState(() => _saving = true);
    try {
      // D45: Key 留空且已配置时, 后端会用运行时覆盖层的旧值
      final key = _keyCtrl.text.trim();
      await ref
          .read(llmProvidersProvider.notifier)
          .saveAndRefresh(
            provider: widget.provider.id,
            apiKey: key,
            baseUrl: _urlCtrl.text.trim(),
            defaultModel: _modelCtrl.text.trim(),
          );
      _keyCtrl.clear();
      if (!mounted) return;
      // D45: 保存成功后自动退出编辑模式, 回到查看模式显示新 Key
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.provider.name} 配置已保存'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onSwitchDefault(String providerId) async {
    try {
      await ref.read(llmProvidersProvider.notifier).switchDefault(providerId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已切换默认运营商: ${widget.provider.name}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('切换失败: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onClear(String providerId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('清除运行时配置'),
            content: Text(
              '清除 ${widget.provider.name} 的运行时配置? 清除后回退到 .env 环境变量配置。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                child: const Text('清除'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(llmProvidersProvider.notifier).clear(providerId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.provider.name} 运行时配置已清除'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('清除失败: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// D45: 信息行 (label: value) — 查看模式用
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppPalette.textTertiary(b),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 子组件
// ============================================================

class _FieldLabel extends StatelessWidget {
  final String label;
  final String hint;
  const _FieldLabel({required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            hint,
            style: TextStyle(fontSize: 10, color: AppPalette.textTertiary(b)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
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

class _TestResultView extends StatelessWidget {
  final LlmTestResult result;
  const _TestResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final color = result.ok ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(S.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                result.ok
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                result.ok
                    ? '连通正常  ${result.latencyMs} ms'
                    : '连通失败  ${result.latencyMs} ms',
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (result.error.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              result.error,
              style: TextStyle(
                fontSize: 11,
                color: AppPalette.textSecondary(b),
              ),
            ),
          ],
          if (result.ok && result.responsePreview.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '响应预览: ${result.responsePreview}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppPalette.textTertiary(b)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 运营商图标 (按 id 选 Material icon + 颜色)
class _ProviderIcon extends StatelessWidget {
  final String providerId;
  final double size;
  const _ProviderIcon({required this.providerId, required this.size});

  @override
  Widget build(BuildContext context) {
    final cfg = _iconConfig[providerId] ?? _iconConfig['custom']!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cfg.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(cfg.icon, size: size * 0.6, color: cfg.color),
    );
  }
}

class _IconCfg {
  final IconData icon;
  final Color color;
  const _IconCfg(this.icon, this.color);
}

const Map<String, _IconCfg> _iconConfig = {
  'deepseek': _IconCfg(Icons.psychology_rounded, Color(0xFF4D6BFE)),
  'openai': _IconCfg(Icons.bolt_rounded, Color(0xFF10A37F)),
  'qwen': _IconCfg(Icons.cloud_rounded, Color(0xFF615CED)),
  'zhipu': _IconCfg(Icons.auto_awesome_rounded, Color(0xFF3859FF)),
  'custom': _IconCfg(Icons.tune_rounded, Color(0xFF8E8E93)),
};
