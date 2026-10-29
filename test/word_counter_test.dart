// =============================================================================
// ShuFang — Word Counter Tests
// =============================================================================
// -----------------------------------------------------------------------------

import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/utils/word_counter.dart';

void main() {
  group('WordCounter.count', () {
    test('Empty string returns 0', () {
      expect(WordCounter.count(''), 0);
    });

    test('ASCII counts chars (excluding whitespace)', () {
      expect(WordCounter.count('hello world'), 10);
    });

    test('CJK counts chars', () {
      expect(WordCounter.count('你好世界'), 4);
    });

    test('Mixed counts all non-whitespace chars', () {
      expect(WordCounter.count('hello 你好'), 7);
    });

    test('Multiple newlines are collapsed to 0 contribution', () {
      expect(WordCounter.count('a\n\n\nb'), 2);
    });

    test('Tabs and spaces are stripped', () {
      expect(WordCounter.count('a\t  b  c'), 3);
    });
  });

  group('WordCounter.cjkCount', () {
    test('Returns 0 for empty', () {
      expect(WordCounter.cjkCount(''), 0);
    });

    test('Counts CJK Unified Ideographs', () {
      expect(WordCounter.cjkCount('你好世界'), 4);
    });

    test('Does not count ASCII letters', () {
      expect(WordCounter.cjkCount('hello world'), 0);
    });

    test('Counts CJK punctuation', () {
      expect(WordCounter.cjkCount('你好，世界。'), 6);
    });

    test('Mixed: counts CJK only', () {
      expect(WordCounter.cjkCount('hello 你好 world 世界'), 4);
    });
  });

  group('WordCounter.format', () {
    test('Less than 1000: no separator', () {
      expect(WordCounter.format(0), '0');
      expect(WordCounter.format(123), '123');
      expect(WordCounter.format(999), '999');
    });

    test('1000+ uses comma separator', () {
      expect(WordCounter.format(1000), '1,000');
      expect(WordCounter.format(12345), '12,345');
      expect(WordCounter.format(1000000), '1,000,000');
    });

    test('Edge cases', () {
      expect(WordCounter.format(1234), '1,234');
      expect(WordCounter.format(1234567890), '1,234,567,890');
    });
  });
}
