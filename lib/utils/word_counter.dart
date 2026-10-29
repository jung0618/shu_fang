// =============================================================================
// ShuFang Design System — Word Counter Utility
// =============================================================================
// 统一处理中英文/标点字数统计。
// -----------------------------------------------------------------------------

class WordCounter {
  WordCounter._();

  /// 统计字符数。
  /// - 中文/全角字符按 1 字计
  /// - 英文/拉丁字符按 1 字计
  /// - 空白字符不计入
  /// - 标点符号按 1 字计
  static int count(String text) {
    if (text.isEmpty) return 0;
    // 去掉所有空白（含换行）
    final cleaned = text.replaceAll(RegExp(r'\s+'), '');
    return cleaned.length;
  }

  /// 统计"有效字数"——按 CJK 区段计数（与中文字数统计常用法一致）。
  /// 简单近似：剔除空白后字符数 - 半角数字/英文字母 + 整句中的中文段落按段乘 1。
  static int cjkCount(String text) {
    if (text.isEmpty) return 0;
    final cleaned = text.replaceAll(RegExp(r'\s+'), '');
    var n = 0;
    for (final ch in cleaned.runes) {
      // CJK Unified Ideographs + 扩展 + 标点 + Hiragana/Katakana
      if ((ch >= 0x4E00 && ch <= 0x9FFF) ||
          (ch >= 0x3000 && ch <= 0x303F) ||
          (ch >= 0xFF00 && ch <= 0xFFEF) ||
          (ch >= 0x3040 && ch <= 0x30FF) ||
          (ch >= 0x3400 && ch <= 0x4DBF)) {
        n += 1;
      }
    }
    return n;
  }

  /// 格式化为带千分位的字符串 (例: 12,345)
  static String format(int n) {
    final str = n.toString();
    if (str.length <= 3) return str;
    final buffer = StringBuffer();
    var count = 0;
    for (var i = str.length - 1; i >= 0; i--) {
      buffer.write(str[i]);
      count++;
      if (count % 3 == 0 && i != 0) {
        buffer.write(',');
      }
    }
    return buffer.toString().split('').reversed.join();
  }
}
