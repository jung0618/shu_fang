// 项目工作区 — D26 整合: 设定集 + 单元集 + 大纲 + 矩阵 + 审阅 + 预设 (6 Tab)
//
// 设计原则:
// - 管理类功能独立页面, 不干扰写作 (Scrivener 研究文件夹模式)
// - Tab 并列同质, ≤7 阈值, 无需分组 [层级·7阈值]
// - 写作 → 项目 入后退栈, 可返回写作 [导航·后退栈]
// - D26 #6: 审阅从顶级路由下降, 整合到项目 Tab
// - D26 #10: 预设(原工程)与项目合并, 整合到项目 Tab — 作家术语, 不叫 "工程"

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/theme.dart';
import '../widgets/settings_files_page.dart';
import '../widgets/unit_sets_page.dart';
import '../widgets/outline_generator.dart';
import '../widgets/unit_matrix_view.dart';
// D26 #6: 审阅组件
import '../widgets/review_panel.dart';
import '../widgets/active_review_panel.dart';
import '../widgets/style_panel.dart';
// D26 #10: 预设(原工程)组件 — 资料库/就绪度/导出, 全部作家工具
import '../widgets/lore_builder.dart';
import '../widgets/readiness_checker.dart';
import '../widgets/export_panel.dart';

class ProjectPage extends ConsumerStatefulWidget {
  /// D26 #6/10: 支持从顶级路由 review/engineering 直接跳到对应 Tab
  final int initialTab;
  const ProjectPage({super.key, this.initialTab = 0});

  @override
  ConsumerState<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends ConsumerState<ProjectPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final Set<int> _visitedTabs = {0};

  // D26 #6/#10: 新增 审阅 (4) + 预设 (5), 共 6 Tab
  // (按 Hick 定律, 6 < 7 阈值, 不需分组)
  // 预设是作家术语, 内容为: 资料库构建 / 就绪度检查 / 导出
  static const _tabs = [
    (text: '设定集', icon: Icons.description_outlined),
    (text: '单元集', icon: Icons.inventory_2_outlined),
    (text: '大纲', icon: Icons.list_alt_rounded),
    (text: '矩阵', icon: Icons.grid_on_outlined),
    (text: '审阅', icon: Icons.rate_review_outlined),
    (text: '预设', icon: Icons.tune_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, _tabs.length - 1),
    );
    _tabController.addListener(_onTabChanged);
    // D26: 启动时即标记 initialTab 为已访问, 立即渲染
    if (widget.initialTab > 0) _visitedTabs.add(widget.initialTab);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      if (!_visitedTabs.contains(_tabController.index)) {
        setState(() => _visitedTabs.add(_tabController.index));
      }
    }
  }

  Widget _buildPanel(int index) {
    if (!_visitedTabs.contains(index)) return const SizedBox.shrink();
    return switch (index) {
      0 => const SettingsFilesPage(),
      1 => const UnitSetsPage(),
      2 => const OutlineGenerator(),
      3 => const UnitMatrixView(),
      4 => const _ReviewWorkspace(),  // D26 #6: 审阅 (4 子 tab)
      5 => const _PresetWorkspace(),  // D26 #10: 预设 (3 子 tab, 原"工程"改名)
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        title: const Text('项目'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.sm),
          tabs: [for (final t in _tabs) Tab(text: t.text, icon: Icon(t.icon, size: 16))],
        ),
      ),
      body: IndexedStack(
        index: _tabController.index,
        children: [for (int i = 0; i < _tabs.length; i++) _buildPanel(i)],
      ),
    );
  }
}

// ============================================================
// D26 #6: 审阅工作区 (4 子 tab) — 嵌入项目 Tab 5
// ============================================================
class _ReviewWorkspace extends ConsumerStatefulWidget {
  const _ReviewWorkspace();

  @override
  ConsumerState<_ReviewWorkspace> createState() => _ReviewWorkspaceState();
}

class _ReviewWorkspaceState extends ConsumerState<_ReviewWorkspace>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  static const _subTabs = [
    (text: '段落审阅', icon: Icons.edit_note_rounded),
    (text: '跨章审阅', icon: Icons.menu_book_rounded),
    (text: '主动评审', icon: Icons.quiz_outlined),
    (text: '文风分析', icon: Icons.palette_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _subTabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          ),
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding:
                const EdgeInsets.symmetric(horizontal: S.lg, vertical: 6),
            tabs: [
              for (final t in _subTabs)
                Tab(text: t.text, icon: Icon(t.icon, size: 14)),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab.index,
            children: const [
              ReviewPanel(mode: 'paragraph'),
              ReviewPanel(mode: 'cross-chapter'),
              ActiveReviewPanel(),
              StylePanel(),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// D26 #10: 预设工作区 (3 子 tab) — 嵌入项目 Tab 6
// 作家术语, 原"工程"改名. 内容: 资料库构建 / 就绪度 / 导出
// ============================================================
class _PresetWorkspace extends ConsumerStatefulWidget {
  const _PresetWorkspace();

  @override
  ConsumerState<_PresetWorkspace> createState() =>
      _PresetWorkspaceState();
}

class _PresetWorkspaceState extends ConsumerState<_PresetWorkspace>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // 作家友好的子 tab 名 (避免开发者术语)
  // 资料库 = lore/setting 库, 就绪度 = 完成度自检, 导出 = 输出作品
  static const _subTabs = [
    (text: '资料库', icon: Icons.account_tree_outlined),
    (text: '就绪度', icon: Icons.checklist_outlined),
    (text: '导出', icon: Icons.upload_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _subTabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          ),
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding:
                const EdgeInsets.symmetric(horizontal: S.lg, vertical: 6),
            tabs: [
              for (final t in _subTabs)
                Tab(text: t.text, icon: Icon(t.icon, size: 14)),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab.index,
            children: const [
              LoreBuilder(),
              ReadinessChecker(),
              ExportPanel(),
            ],
          ),
        ),
      ],
    );
  }
}
