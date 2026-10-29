// 轻量 Markdown 渲染 widget — 设定/灵感页用
// 不依赖 flutter_markdown 包, 自己解析 + RichText 渲染
// 支持: #/##/### 标题, **加粗**, *斜体*, - 列表, > 引用, `代码`, 段落, ---分隔线
// 不支持: 表格/链接/图片/嵌套列表 (设定集场景够用)

import 'package:flutter/material.dart';

class MarkdownView extends StatelessWidget {
  final String data;
  final bool editable;
  final EdgeInsets padding;

  const MarkdownView({
    super.key,
    required this.data,
    this.editable = false,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = data.split('\n');
    final blocks = <Widget>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      // 空行跳过
      if (trimmed.isEmpty) {
        continue;
      }

      // 分隔线 ---
      if (trimmed == '---' || trimmed == '***') {
        blocks.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(
            color: theme.dividerColor.withValues(alpha: 0.5),
            height: 1,
          ),
        ));
        continue;
      }

      // 标题 # / ## / ###
      if (trimmed.startsWith('### ')) {
        blocks.add(_buildHeading(
          trimmed.substring(4),
          theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) ??
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          theme,
        ));
        continue;
      }
      if (trimmed.startsWith('## ')) {
        blocks.add(_buildHeading(
          trimmed.substring(3),
          theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700) ??
              const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          theme,
        ));
        continue;
      }
      if (trimmed.startsWith('# ')) {
        blocks.add(_buildHeading(
          trimmed.substring(2),
          theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800) ??
              const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          theme,
        ));
        continue;
      }

      // 引用 >
      if (trimmed.startsWith('> ')) {
        blocks.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
                width: 3,
              ),
            ),
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
          ),
          child: _buildInlineRich(
            trimmed.substring(2),
            theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  fontStyle: FontStyle.italic,
                ) ??
                const TextStyle(fontStyle: FontStyle.italic),
            theme,
          ),
        ));
        continue;
      }

      // 列表项 - / * / 数字.
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 8),
                child: Text('•',
                    style: TextStyle(
                        color: theme.colorScheme.primary, fontSize: 14)),
              ),
              Expanded(
                child: _buildInlineRich(
                  trimmed.substring(2),
                  theme.textTheme.bodyMedium ??
                      const TextStyle(fontSize: 14, height: 1.6),
                  theme,
                ),
              ),
            ],
          ),
        ));
        continue;
      }
      final orderedMatch = RegExp(r'^(\d+)\.\s+(.*)').firstMatch(trimmed);
      if (orderedMatch != null) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: Text('${orderedMatch.group(1)}.',
                    style: TextStyle(
                        color: theme.colorScheme.primary, fontSize: 13)),
              ),
              Expanded(
                child: _buildInlineRich(
                  orderedMatch.group(2)!,
                  theme.textTheme.bodyMedium ??
                      const TextStyle(fontSize: 14, height: 1.6),
                  theme,
                ),
              ),
            ],
          ),
        ));
        continue;
      }

      // 普通段落
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _buildInlineRich(
          trimmed,
          theme.textTheme.bodyMedium?.copyWith(height: 1.7) ??
              const TextStyle(fontSize: 14, height: 1.7),
          theme,
        ),
      ));
    }

    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks,
      ),
    );
  }

  Widget _buildHeading(String text, TextStyle style, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: _buildInlineRich(text, style, theme),
    );
  }

  /// 解析行内 **加粗** / *斜体* / `代码` 并构建 TextSpan
  Widget _buildInlineRich(String text, TextStyle baseStyle, ThemeData theme) {
    return RichText(
      text: _parseInline(text, baseStyle, theme),
      softWrap: true,
    );
  }

  TextSpan _parseInline(String text, TextStyle base, ThemeData theme) {
    final children = <TextSpan>[];
    // 正则: **bold** | *italic* | `code`
    final regex = RegExp(r'(\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`)');
    int lastEnd = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        children.add(TextSpan(
            text: text.substring(lastEnd, match.start), style: base));
      }
      final full = match.group(0)!;
      if (full.startsWith('**')) {
        // 加粗
        children.add(TextSpan(
          text: match.group(2),
          style: base.copyWith(fontWeight: FontWeight.w700),
        ));
      } else if (full.startsWith('`')) {
        // 代码
        children.add(TextSpan(
          text: match.group(4),
          style: base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.6),
            color: theme.colorScheme.primary,
          ),
        ));
      } else if (full.startsWith('*')) {
        // 斜体
        children.add(TextSpan(
          text: match.group(3),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ));
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      children.add(
          TextSpan(text: text.substring(lastEnd), style: base));
    }
    return TextSpan(children: children);
  }
}
