/// 主页写作热力图组件 (抽离自 home_dashboard_page.dart)
///
/// 包含:
/// - HomeHeatmapSection: 整个热力图卡片 (标题 + 网格 + 图例)
/// - HomeHeatmapGrid: 53 周 × 7 天格子
/// - HomeHeatmapLegend: 强度图例
library;

import 'package:flutter/material.dart';

import '../components/app_components.dart';
import '../pages/home_dashboard_data.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';

// ============================================================
// 热力图 (365 天, 7 色调强度)
// ============================================================

class HomeHeatmapSection extends StatelessWidget {
  final WritingHeatmapData data;
  final Brightness brightness;
  const HomeHeatmapSection({super.key, required this.data, required this.brightness});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department_outlined,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: S.xs),
              Text('写作热力图',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text(
                '近 ${data.totalDays} 天 · ${_formatCount(data.totalWords)} 字',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppPalette.textTertiary(brightness),
                    ),
              ),
            ],
          ),
          const SizedBox(height: S.md),
          HomeHeatmapGrid(data: data, brightness: brightness),
          const SizedBox(height: S.sm),
          HomeHeatmapLegend(brightness: brightness),
        ],
      ),
    );
  }

  String _formatCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class HomeHeatmapGrid extends StatelessWidget {
  final WritingHeatmapData data;
  final Brightness brightness;
  const HomeHeatmapGrid({super.key, required this.data, required this.brightness});

  @override
  Widget build(BuildContext context) {
    // 53 周 × 7 天 = 371 天, 取最近 365
    final weeks = <List<int>>[];
    final padded = List<int>.from(data.dailyWords);
    // 前补 0 让周对齐 (假设从周日开始, 取最后 53 周 = 371)
    while (padded.length < 53 * 7) {
      padded.insert(0, 0);
    }
    for (var w = 0; w < 53; w++) {
      weeks.add(padded.sublist(w * 7, (w + 1) * 7));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var w = 0; w < weeks.length; w++) ...[
            Column(
              children: [
                for (var d = 0; d < 7; d++) _buildCell(weeks[w][d]),
              ],
            ),
            if (w < weeks.length - 1) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }

  Widget _buildCell(int wordCount) {
    final intensity = data.intensityOf(wordCount);
    return Container(
      width: 11,
      height: 11,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: _colorForIntensity(intensity, brightness),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Color _colorForIntensity(int level, Brightness b) {
    return HeatmapPalette.colorForLevel(level, b);
  }
}

class HomeHeatmapLegend extends StatelessWidget {
  final Brightness brightness;
  const HomeHeatmapLegend({super.key, required this.brightness});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('少',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textTertiary(brightness),
                )),
        const SizedBox(width: S.xs),
        for (var i = 0; i < 5; i++) ...[
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: _legendColor(i, brightness),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (i < 4) const SizedBox(width: 2),
        ],
        const SizedBox(width: S.xs),
        Text('多',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textTertiary(brightness),
                )),
      ],
    );
  }

  Color _legendColor(int level, Brightness b) {
    return HeatmapPalette.colorForLevel(level, b);
  }
}
