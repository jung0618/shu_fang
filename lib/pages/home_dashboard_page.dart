/// 书坊 ShuFang 主页（启动页 / Dashboard）
///
/// 布局：
/// ```
/// ┌──────────────────────────────────────────────────────────┐
/// │ 账号头像 (右上)        书坊 · 主题切换                    │ ← 顶栏
/// ├──────────────────────────────────────────────────────────┤
/// │ 灵感入口  │ 单元集入口  │ 设定集入口  │ 训练入口          │ ← 侧边入口条
/// ├──────────────────────────────────────────────────────────┤
/// │ 写作热力图 (近 365 天 · 7 色调强度)                       │ ← 热力图
/// │ ▢▢▢▣▣▢▢▢▣▣▢▢▢▣▣▢▢▢▣▣▢▢▢▣▣                            │
/// │ ▢▢▣▣▣▣▢▢▢▣▣▣▢▢▢▣▣▣▢▢▢▣▣▣                            │
/// ├──────────────────────────────────────────────────────────┤
/// │  📖 选择书籍                                              │
/// │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐                  │
/// │  │ 书1  │  │ 书2  │  │ 书3  │  │  +   │                  │ ← 卡片网格
/// │  └──────┘  └──────┘  └──────┘  └──────┘                  │
/// ├──────────────────────────────────────────────────────────┤
/// │ 📚 设定集预览                                             │
/// │ • 主角设定.md   2 天前  1.2K                             │ ← 文件名预览
/// │ • 世界观.md     5 天前  3.4K                             │
/// │ • 伏笔追踪.md   1 周前  800                              │
/// └──────────────────────────────────────────────────────────┘
/// ```
///
/// **数据源**: mock 数据 (不依赖后端 API, 启动即可用)
/// **后续**: 接入 `GET /api/stats/writing-heatmap` 和 `GET /api/lore/recent` 后替换
///
/// 拆分: 数据模型/Provider → home_dashboard_data.dart
///       热力图 → widgets/home_heatmap.dart
///       新闻条 → widgets/home_news_ticker.dart
///       书卡 → widgets/home_book_section.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';

import '../components/app_components.dart';
import '../services/engine_launcher.dart';
import '../store/editor_store.dart';
import '../theme/colors.dart';
import '../theme/motion.dart';
import '../theme/radius.dart';
import '../theme/spacing.dart';
import '../widgets/drift_reveal.dart';
import '../widgets/home_book_section.dart';
import '../widgets/home_heatmap.dart';
import '../widgets/home_news_ticker.dart';
import '../widgets/user_center.dart';
import 'home_dashboard_data.dart';

// ============================================================
// 主页
// ============================================================

class HomeDashboardPage extends ConsumerStatefulWidget {
  /// D26 #8: 从顶级 inspire 路由跳转时, 主页 quick action 区自动滚动 + 高亮
  final bool initialInspireFocus;
  const HomeDashboardPage({super.key, this.initialInspireFocus = false});

  @override
  ConsumerState<HomeDashboardPage> createState() => _HomeDashboardPageState();
}

class _HomeDashboardPageState extends ConsumerState<HomeDashboardPage> {
  // D26 #8: 灵感快捷入口的 GlobalKey, 用于从顶级路由跳入时滚动到位
  final _inspireActionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.initialInspireFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusInspire());
    }
  }

  void _focusInspire() {
    final ctx = _inspireActionKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: Motion.medium,
      curve: Curves.easeInOut,
      alignment: 0.1,
    );
  }

  @override
  Widget build(BuildContext context) {
    // D37 Phase 3-2: heatmapProvider 改 FutureProvider, valueOrNull 兼容
    final heatmapAsync = ref.watch(heatmapProvider);
    final heatmap = heatmapAsync.valueOrNull ?? WritingHeatmapData.mock();
    final booksAsync = ref.watch(homeBooksProvider);
    final lore = ref.watch(loreProvider);
    final b = Theme.of(context).brightness;
    // Phase 3.2: booksProvider 改为 FutureProvider, 用 valueOrNull 同步取值
    // loading/error 时显示空列表 (后续可加 loading 指示)
    final books = booksAsync.valueOrNull ?? [];

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _TopBar(brightness: b)),
            SliverToBoxAdapter(
              // D26 #8: GlobalKey 用于从顶级 inspire 路由跳入时滚动到位
              child: Container(
                key: _inspireActionKey,
                child: _QuickAccessStrip(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.xl, 0),
                child: HomeHeatmapSection(data: heatmap, brightness: b),
              ),
            ),
            // 滚动动态条 — 紧跟热力图, 提示近期活动
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.xl, S.md, S.xl, 0),
                child: HomeNewsTicker(brightness: b),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.xl, S.xl, S.xl, 0),
                child: HomeBookSection(books: books, brightness: b),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.xl, S.xl, S.xl, S.xxl),
                child: _LoreSection(files: lore, brightness: b),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 顶栏 — 品牌 + 账号头像
// ============================================================

class _TopBar extends ConsumerWidget {
  final Brightness brightness;
  const _TopBar({required this.brightness});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.xl, vertical: S.md),
      child: Row(
        children: [
          const BrandHeader(subtitle: '主页'),
          const Spacer(),
          // D26 #7: 引擎状态指示在顶栏 (右侧), 一目了然
          const _EngineStatusChip(),
          const SizedBox(width: S.sm),
          IconButton(
            icon: const Icon(Icons.brightness_6_outlined),
            tooltip: '切换主题',
            onPressed: () {
              final m = ref.read(themeModeProvider);
              ref.read(themeModeProvider.notifier).state =
                  m == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          const SizedBox(width: S.xs),
          _AccountAvatar(brightness: brightness),
        ],
      ),
    );
  }
}

/// 顶栏引擎状态指示 (D26 #7 + T-18: 联动全局 engineStatusProvider)
class _EngineStatusChip extends ConsumerStatefulWidget {
  const _EngineStatusChip();

  @override
  ConsumerState<_EngineStatusChip> createState() => _EngineStatusChipState();
}

class _EngineStatusChipState extends ConsumerState<_EngineStatusChip> {
  @override
  void initState() {
    super.initState();
    // T-18: 初始探测 (仅当状态为 unknown 时)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(engineStatusProvider) == EngineStatus.unknown) {
        EngineLauncher.probeEngine(ref);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    ref.watch(engineBindingProvider);
    final reported = ref.watch(engineStatusProvider);
    final status =
        reported == EngineStatus.ready && !apiClient.canUseWorkspace
            ? EngineStatus.failed
            : reported;
    final (icon, text, color) = switch (status) {
      EngineStatus.ready => (Icons.bolt_rounded, '引擎已连接', AppColors.success),
      EngineStatus.starting => (Icons.sync_rounded, '启动中...', AppColors.info),
      EngineStatus.failed => (
        Icons.power_settings_new_rounded,
        '引擎未启动',
        AppColors.warning,
      ),
      EngineStatus.unknown => (
        Icons.help_outline_rounded,
        '探测中...',
        AppPalette.textTertiary(b),
      ),
    };
    return Tooltip(
      message:
          status == EngineStatus.ready
              ? '已核对当前工作区；点击查看能力详情'
              : (status == EngineStatus.failed ? '点击启动引擎' : '正在探测/启动引擎...'),
      child: InkWell(
        onTap: () => showUserCenter(context, ref),
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            border: Border.all(color: color.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status == EngineStatus.starting ||
                  status == EngineStatus.unknown)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                )
              else
                Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 账号头像 — 点击进用户中心 (D26 #9 修复: 之前用户找不到用户中心)
class _AccountAvatar extends ConsumerWidget {
  final Brightness brightness;
  const _AccountAvatar({required this.brightness});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: '工作区与工具',
      child: InkWell(
        onTap: () => showUserCenter(context, ref),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.aiGradientStart, AppColors.aiGradientEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '我',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 快速入口条 — 灵感 / 单元集 / 设定集 / 训练
// ============================================================

class _QuickAccessStrip extends ConsumerWidget {
  const _QuickAccessStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phase 3.4: DriftReveal 唯一用法 — 主页快速入口条 emoji 按钮
    // 默认态: 仅 emoji (无文字); hover: emoji 淡出, 文字展开
    final items = <_QuickItem>[
      const _QuickItem(emoji: '💡', label: '灵感', route: AppRoute.inspire),
      const _QuickItem(emoji: '📦', label: '单元集', route: AppRoute.project),
      const _QuickItem(emoji: '📄', label: '设定集', route: AppRoute.project),
      // D26 #10: "训练" → "预设" (作家术语, 配合 Tab 6)
      const _QuickItem(emoji: '⚙️', label: '预设', route: AppRoute.engineering),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.xl, vertical: S.sm),
      child: Row(
        children: [
          for (final item in items) ...[
            Expanded(child: _QuickAccessButton(item: item)),
            if (item != items.last) const SizedBox(width: S.sm),
          ],
        ],
      ),
    );
  }
}

class _QuickItem {
  final String emoji;
  final String label;
  final AppRoute route;
  const _QuickItem({
    required this.emoji,
    required this.label,
    required this.route,
  });
}

class _QuickAccessButton extends ConsumerWidget {
  final _QuickItem item;
  const _QuickAccessButton({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = Theme.of(context).brightness;
    return AppCard(
      onTap: () {
        ref.read(appRouteProvider.notifier).state = item.route;
      },
      padding: const EdgeInsets.symmetric(vertical: S.md, horizontal: S.sm),
      child: SizedBox(
        height: 48,
        child: DriftReveal(
          driftDirection: DriftDirection.up,
          driftDistance: 0,
          hoverPadding: 4,
          externalHint: DriftHint.chevronRight,
          duration: const Duration(milliseconds: 800),
          // 默认态: 仅 emoji 大图标 (无文字)
          placeholder: Center(
            child: Text(item.emoji, style: const TextStyle(fontSize: 28)),
          ),
          // hover: emoji 淡出, 文字展开 (emoji → text 单次切换, 不共存)
          reveal: Center(
            child: Text(
              item.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppPalette.textPrimary(b),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 设定集预览 (小区域)
// ============================================================

class _LoreSection extends ConsumerWidget {
  final List<LoreFilePreview> files;
  final Brightness brightness;
  const _LoreSection({required this.files, required this.brightness});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.folder_outlined,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: S.xs),
              Text('设定集', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                onPressed:
                    () =>
                        ref.read(appRouteProvider.notifier).state =
                            AppRoute.project,
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('打开项目'),
              ),
            ],
          ),
          const SizedBox(height: S.sm),
          for (final f in files) _LoreFileRow(file: f, brightness: brightness),
        ],
      ),
    );
  }
}

class _LoreFileRow extends StatelessWidget {
  final LoreFilePreview file;
  final Brightness brightness;
  const _LoreFileRow({required this.file, required this.brightness});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.xs),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: 14,
            color: AppPalette.textTertiary(brightness),
          ),
          const SizedBox(width: S.xs),
          Expanded(
            child: Text(
              file.name,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: S.sm),
          Text(
            _formatSize(file.sizeBytes),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppPalette.textTertiary(brightness),
            ),
          ),
          const SizedBox(width: S.md),
          Text(
            file.lastModified,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppPalette.textTertiary(brightness),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
    return '${bytes}B';
  }
}
