import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../store/editor_store.dart';
import '../utils/highlight_parser.dart';

/// 编辑区右侧浮动小地图 — D21 重构
///   位置: 编辑区最右上角 (浮层, 由 editor_page 用 Stack 包住)
///   尺寸: 60px → 20px (≈ 1/3)
///   样式: 半透明, 作为行级指示器
class Minimap extends ConsumerStatefulWidget {
  final String text;
  final ScrollController scrollController;
  final VoidCallback? onToggle;

  const Minimap({
    super.key,
    required this.text,
    required this.scrollController,
    this.onToggle,
  });

  @override
  ConsumerState<Minimap> createState() => _MinimapState();
}

class _MinimapState extends ConsumerState<Minimap> {
  double _hoverY = -1;

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(showMinimapProvider);
    if (!visible) {
      // 折叠状态: 16px 极窄 (不抢空间)
      return Opacity(
        opacity: 0.5,
        child: Container(
          width: 16,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.map_outlined, size: 10),
                onPressed: () =>
                    ref.read(showMinimapProvider.notifier).state = true,
                tooltip: '展开缩略图',
                splashRadius: 8,
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      );
    }

    // 展开状态: 20px (原 60px 的 1/3)
    const width = 20.0;
    final highlights = ref.watch(highlightsProvider);
    final sameWords = ref.watch(sameWordHighlightsProvider);
    final activeColor = ref.watch(activeHighlightColorProvider);
    final viewport = ref.watch(viewportRangeProvider);

    return Opacity(
      opacity: 0.55, // 半透明
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Column(
          children: [
            // 头部: 折叠按钮 (极小)
            Container(
              height: 14,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 1),
              child: InkWell(
                onTap: () =>
                    ref.read(showMinimapProvider.notifier).state = false,
                borderRadius: BorderRadius.circular(2),
                child: const Icon(
                  Icons.chevron_right,
                  size: 10,
                ),
              ),
            ),
            // 缩略图绘制区
            // 性能优化: RepaintBoundary 隔离重绘区域, hover/scroll 时只重绘 minimap, 不影响编辑器
            Expanded(
              child: RepaintBoundary(
                child: GestureDetector(
                  onTapDown: _onTapDown,
                  onVerticalDragUpdate: _onDragUpdate,
                  child: MouseRegion(
                    onHover: (event) {
                      // 性能优化: 节流 hover, 仅当 Y 变化 > 1px 时才 setState
                      final dy = event.localPosition.dy;
                      if ((dy - _hoverY).abs() > 1.0) {
                        setState(() => _hoverY = dy);
                      }
                    },
                    onExit: (_) {
                      if (_hoverY != -1) {
                        setState(() => _hoverY = -1);
                      }
                    },
                    child: CustomPaint(
                      painter: _MinimapPainter(
                        text: widget.text,
                        highlights: highlights,
                        sameWords: sameWords,
                        activeColor: activeColor,
                        viewport: viewport,
                        hoverY: _hoverY,
                        theme: Theme.of(context),
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onTapDown(TapDownDetails details) {
    _scrollToY(details.localPosition.dy);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _scrollToY(details.localPosition.dy);
  }

  void _scrollToY(double dy) {
    final totalLines = HighlightParser.totalLines(widget.text);
    if (totalLines <= 0) return;

    final renderHeight = context.size?.height ?? 0;
    if (renderHeight <= 14) return; // 减去头部高度

    final lineH = (renderHeight - 14) / totalLines;
    final targetLine = (dy - 14) / lineH;
    final scrollOffset = targetLine * _estimatedLineHeight();

    widget.scrollController.jumpTo(
      scrollOffset.clamp(0.0, widget.scrollController.position.maxScrollExtent),
    );
  }

  double _estimatedLineHeight() {
    return 16.0 * 1.8;
  }
}

/// Minimap 自绘引擎 (20px 窄宽版)
class _MinimapPainter extends CustomPainter {
  final String text;
  final List<HighlightMark> highlights;
  final List<SameWordMatch> sameWords;
  final HighlightColor? activeColor;
  final ViewportRange viewport;
  final double hoverY;
  final ThemeData theme;

  // 1.8 → 1.2 适应窄宽
  static const double lineH = 1.2;
  static const double charW = 0.3;

  _MinimapPainter({
    required this.text,
    required this.highlights,
    required this.sameWords,
    required this.activeColor,
    required this.viewport,
    required this.hoverY,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty) return;

    final lines = text.split('\n');
    final totalLines = lines.length;
    final drawWidth = size.width;

    final textPaint = Paint()
      ..color = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4) ??
          const Color(0xFF999999);
    final titlePaint = Paint()
      ..color = theme.colorScheme.primary.withValues(alpha: 0.7);
    final sameWordPaint = Paint()
      ..color = const Color(0xFFFF9800).withValues(alpha: 0.5);

    int offset = 0;
    final lineOffsets = <int>[];
    for (int i = 0; i < totalLines; i++) {
      lineOffsets.add(offset);
      offset += lines[i].length + 1;
    }

    final lineHighlightColors = <int, List<HighlightColor>>{};
    final lineSameWord = <int, bool>{};
    for (final h in highlights) {
      final startLine = _offsetToLine(h.startOffset, lineOffsets);
      final endLine = _offsetToLine(h.endOffset, lineOffsets);
      for (int i = startLine; i <= endLine && i < totalLines; i++) {
        lineHighlightColors.putIfAbsent(i, () => []).add(h.color);
      }
    }
    for (final m in sameWords) {
      final startLine = _offsetToLine(m.startOffset, lineOffsets);
      final endLine = _offsetToLine(m.endOffset, lineOffsets);
      for (int i = startLine; i <= endLine && i < totalLines; i++) {
        lineSameWord[i] = true;
      }
    }

    for (int i = 0; i < totalLines; i++) {
      final y = i * lineH;
      if (y > size.height) break;

      final line = lines[i];

      if (lineHighlightColors.containsKey(i)) {
        final colors = lineHighlightColors[i]!;
        for (final color in colors) {
          final isActive = activeColor == color;
          final paint = Paint()
            ..color = isActive
                ? color.activeColor.withValues(alpha: 0.7)
                : color.minimapColor.withValues(alpha: 0.7);
          final w = math.min(line.length * charW, drawWidth);
          canvas.drawRect(Rect.fromLTWH(0, y, w, lineH), paint);
        }
      } else if (lineSameWord[i] == true) {
        final w = math.min(line.length * charW, drawWidth);
        canvas.drawRect(Rect.fromLTWH(0, y, w, lineH), sameWordPaint);
      } else if (line.startsWith('#')) {
        final w = math.min(line.length * charW, drawWidth);
        canvas.drawRect(Rect.fromLTWH(0, y, w, lineH), titlePaint);
      } else if (line.trim().isNotEmpty) {
        final w = math.min(line.length * charW, drawWidth);
        canvas.drawRect(Rect.fromLTWH(0, y, w, lineH), textPaint);
      }
    }

    // Viewport 指示器
    if (viewport.lastLine > 0) {
      final vy = viewport.firstLine * lineH;
      final vh = (viewport.lastLine - viewport.firstLine) * lineH;
      final viewportPaint = Paint()
        ..color = theme.colorScheme.primary.withValues(alpha: 0.2);
      canvas.drawRect(
        Rect.fromLTWH(0, vy, drawWidth, math.max(vh, lineH * 3)),
        viewportPaint,
      );
      final borderPaint = Paint()
        ..color = theme.colorScheme.primary.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      canvas.drawRect(
        Rect.fromLTWH(0, vy, drawWidth, math.max(vh, lineH * 3)),
        borderPaint,
      );
    }

    // 悬停指示线
    if (hoverY >= 0) {
      final hoverPaint = Paint()
        ..color = theme.colorScheme.primary.withValues(alpha: 0.4)
        ..strokeWidth = 0.5;
      canvas.drawLine(
        Offset(0, hoverY),
        Offset(drawWidth, hoverY),
        hoverPaint,
      );
    }
  }

  int _offsetToLine(int offset, List<int> lineOffsets) {
    int lo = 0, hi = lineOffsets.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (lineOffsets[mid] <= offset) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return hi.clamp(0, lineOffsets.length - 1);
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.highlights != highlights ||
        oldDelegate.sameWords != sameWords ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.viewport != viewport ||
        oldDelegate.hoverY != hoverY;
  }
}
