import 'package:flutter/widgets.dart';

import '../store/editor_store.dart';

/// 支持高亮背景渲染的 TextEditingController
///
/// 覆盖 buildTextSpan: 根据 highlights 把文本切分为多个 TextSpan,
/// 高亮区间用 backgroundColor 渲染, 相同词 (id 以 hl-same- 开头) 用稍淡背景.
/// 这样编辑区文本本身就能看到高亮 (此前只有 minimap 显示, 用户误以为"高亮没用").
class HighlightedTextEditingController extends TextEditingController {
  /// 全部高亮标记 (主高亮 + 相同词高亮, 都带 color)
  /// 相同词标记的 id 以 'hl-same-' 开头, 渲染时颜色更淡
  List<HighlightMark> highlights;

  HighlightedTextEditingController({
    super.text,
    this.highlights = const [],
  });

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    if (text.isEmpty) return TextSpan(text: '', style: style);

    // 排序: 按 start, 主高亮 (非 same) 优先于相同词
    final sorted = [...highlights]..sort((a, b) {
        final c = a.startOffset.compareTo(b.startOffset);
        if (c != 0) return c;
        final aSame = a.id.startsWith('hl-same-');
        final bSame = b.id.startsWith('hl-same-');
        return aSame ? 1 : (bSame ? -1 : 0);
      });

    // 去除越界 & 合并重叠 (保留主高亮, 丢弃被覆盖的相同词)
    final valid = <HighlightMark>[];
    int lastEnd = 0;
    for (final m in sorted) {
      final s = m.startOffset.clamp(0, text.length);
      final e = m.endOffset.clamp(s, text.length);
      if (e <= s) continue; // 空区间
      if (s < lastEnd) continue; // 被前一个高亮覆盖, 跳过
      valid.add(m.copyWith(startOffset: s, endOffset: e));
      lastEnd = e;
    }

    if (valid.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    // 按区间切分文本, 生成 children
    final children = <InlineSpan>[];
    int cursor = 0;
    for (final m in valid) {
      // 普通区间 (cursor → m.start)
      if (m.startOffset > cursor) {
        children.add(TextSpan(
          text: text.substring(cursor, m.startOffset),
          style: style,
        ));
      }
      // 高亮区间 (m.start → m.end): 相同词颜色更淡
      final isSameWord = m.id.startsWith('hl-same-');
      final baseColor = m.color.color;
      final alpha = isSameWord ? (m.color.alpha * 0.6) : m.color.alpha;
      children.add(TextSpan(
        text: text.substring(m.startOffset, m.endOffset),
        style: (style ?? const TextStyle()).copyWith(
          backgroundColor: baseColor.withValues(alpha: alpha),
        ),
      ));
      cursor = m.endOffset;
    }
    // 尾部普通区间
    if (cursor < text.length) {
      children.add(TextSpan(
        text: text.substring(cursor),
        style: style,
      ));
    }

    return TextSpan(style: style, children: children);
  }
}
