import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import '../store/editor_store.dart';

/// 高亮解析工具：查找相同词、计算行偏移等
class HighlightParser {
  /// 在文本中查找所有与 [word] 相同的词的位置
  /// 返回所有匹配的 SameWordMatch 列表
  ///
  /// 注意: 此方法是同步的, 大文本时请用 [findSameWordsAsync] 避免阻塞主线程
  static List<SameWordMatch> findSameWords(String text, String word) {
    if (word.isEmpty || word.trim().isEmpty) return [];
    return _findSameWordsSync(text, word);
  }

  /// 异步查找相同词 (性能优化 UI-2-2)
  /// 大文本 (>5000 字) 时自动走 Isolate, 小文本直接同步执行
  static Future<List<SameWordMatch>> findSameWordsAsync(String text, String word) async {
    if (word.isEmpty || word.trim().isEmpty) return [];
    // 小文本直接同步执行 (避免 Isolate 启动开销 ~1-2ms)
    if (text.length < 5000) {
      return _findSameWordsSync(text, word);
    }
    // 大文本走 Isolate
    try {
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(
        _isolateEntry,
        [receivePort.sendPort, text, word],
      );
      final result = await receivePort.first as String;
      isolate.kill();
      receivePort.close();
      final jsonList = jsonDecode(result) as List<dynamic>;
      return jsonList
          .map((m) => SameWordMatch(
                startOffset: (m as Map<String, dynamic>)['startOffset'] as int,
                endOffset: m['endOffset'] as int,
                word: m['word'] as String,
              ))
          .toList();
    } catch (_) {
      // Isolate 失败时降级为同步
      return _findSameWordsSync(text, word);
    }
  }

  /// 同步查找 (内部使用, 也供 Isolate 调用)
  static List<SameWordMatch> _findSameWordsSync(String text, String word) {
    final matches = <SameWordMatch>[];
    int start = 0;
    while (true) {
      final index = text.indexOf(word, start);
      if (index == -1) break;
      // 检查边界：确保匹配的是完整词
      final beforeOk = index == 0 || _isWordBoundary(text[index - 1]);
      final afterIdx = index + word.length;
      final afterOk = afterIdx >= text.length || _isWordBoundary(text[afterIdx]);
      if (beforeOk && afterOk) {
        matches.add(SameWordMatch(
          startOffset: index,
          endOffset: afterIdx,
          word: word,
        ));
      }
      start = index + 1;
    }
    return matches;
  }

  /// Isolate 入口: 接收 (text, word) tuple, 返回 JSON 编码的匹配列表
  static void _isolateEntry(List<dynamic> args) {
    final sendPort = args[0] as SendPort;
    final text = args[1] as String;
    final word = args[2] as String;
    final matches = _findSameWordsSync(text, word);
    // 序列化为 List<Map> (Isolate 间只能传基本类型)
    final jsonList = matches
        .map((m) => {'startOffset': m.startOffset, 'endOffset': m.endOffset, 'word': m.word})
        .toList();
    sendPort.send(jsonEncode(jsonList));
  }

  /// 判断字符是否为词边界（非字母数字下划线中文字符）
  /// 公开以供 editor_page 共用
  static bool isWordBoundaryChar(String char) {
    if (char.isEmpty) return true;
    final code = char.codeUnitAt(0);
    // ASCII 字母/数字/下划线
    if ((code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        (code >= 0x30 && code <= 0x39) ||
        code == 0x5F) {
      return false;
    }
    // 中文字符
    if ((code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF)) {
      return false;
    }
    return true;
  }

  /// 内部用同名方法，保留兼容
  static bool _isWordBoundary(String char) => isWordBoundaryChar(char);

  /// 将字符偏移转换为行号
  static int offsetToLine(String text, int offset) {
    if (offset <= 0) return 0;
    int line = 0;
    for (int i = 0; i < offset && i < text.length; i++) {
      if (text[i] == '\n') line++;
    }
    return line;
  }

  /// 获取文本总行数
  static int totalLines(String text) {
    if (text.isEmpty) return 1;
    int lines = 1;
    for (int i = 0; i < text.length; i++) {
      if (text[i] == '\n') lines++;
    }
    return lines;
  }

  /// 获取指定行的文本
  static String getLine(String text, int lineNumber) {
    final lines = text.split('\n');
    if (lineNumber < 0 || lineNumber >= lines.length) return '';
    return lines[lineNumber];
  }

  /// 判断指定行是否包含高亮标记
  static List<HighlightColor> highlightColorsOnLine(
    String text,
    int lineNumber,
    List<HighlightMark> highlights,
  ) {
    final lines = text.split('\n');
    int lineStart = 0;
    for (int i = 0; i < lineNumber && i < lines.length; i++) {
      lineStart += lines[i].length + 1; // +1 for \n
    }
    final lineEnd = lineStart + (lineNumber < lines.length ? lines[lineNumber].length : 0);

    final colors = <HighlightColor>{};
    for (final h in highlights) {
      // 高亮范围与行范围有交集
      if (h.startOffset < lineEnd && h.endOffset > lineStart) {
        colors.add(h.color);
      }
    }
    return colors.toList();
  }

  /// 判断指定行是否包含相同词匹配
  static bool hasSameWordOnLine(
    String text,
    int lineNumber,
    List<SameWordMatch> matches,
  ) {
    final lines = text.split('\n');
    int lineStart = 0;
    for (int i = 0; i < lineNumber && i < lines.length; i++) {
      lineStart += lines[i].length + 1;
    }
    final lineEnd = lineStart + (lineNumber < lines.length ? lines[lineNumber].length : 0);

    for (final m in matches) {
      if (m.startOffset < lineEnd && m.endOffset > lineStart) {
        return true;
      }
    }
    return false;
  }

  /// 查找包含指定颜色高亮标记的所有行号
  static List<int> linesWithHighlightColor(
    String text,
    List<HighlightMark> highlights,
    HighlightColor color,
  ) {
    final lines = <int>{};
    final total = totalLines(text);
    final splitLines = text.split('\n');

    int lineStart = 0;
    for (int lineNum = 0; lineNum < total; lineNum++) {
      final lineLen = lineNum < splitLines.length ? splitLines[lineNum].length : 0;
      final lineEnd = lineStart + lineLen;

      for (final h in highlights) {
        if (h.color == color && h.startOffset < lineEnd && h.endOffset > lineStart) {
          lines.add(lineNum);
          break;
        }
      }
      lineStart += lineLen + 1;
    }
    return lines.toList()..sort();
  }
}
