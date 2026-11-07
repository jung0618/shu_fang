// =============================================================================
// ShuFang — Editor Store Tests
// =============================================================================
// 验证状态管理 (Riverpod providers) 的正确性。
// -----------------------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shufang_flutter/store/editor_store.dart';
import 'package:shufang_flutter/services/chapter_save_queue.dart';

ProviderContainer testContainer() => ProviderContainer(
  overrides: [
    chapterSaveQueueProvider.overrideWith((ref) => ChapterSaveQueue()),
    storageRootProvider.overrideWithValue('isolated-test-root'),
  ],
);

void main() {
  group('Editor state providers', () {
    test('editorTextProvider starts empty', () {
      final container = testContainer();
      addTearDown(container.dispose);
      expect(container.read(editorTextProvider), '');
    });

    test('editorTextProvider can be updated', () {
      final container = testContainer();
      addTearDown(container.dispose);
      container.read(editorTextProvider.notifier).state = 'hello';
      expect(container.read(editorTextProvider), 'hello');
    });

    test('saveStatusProvider starts idle', () {
      final container = testContainer();
      addTearDown(container.dispose);
      expect(container.read(saveStatusProvider), SaveStatus.idle);
    });

    test(
      'saveStatusProvider follows the selected chapter draft only',
      () async {
        final container = testContainer();
        addTearDown(container.dispose);
        container.read(currentBookProvider.notifier).state = 'book';
        container.read(currentChapterProvider.notifier).state = 'chapter-a';
        expect(container.read(saveStatusProvider), SaveStatus.idle);
        container
            .read(chapterSaveQueueProvider)
            .stage(
              const ChapterAddress('isolated-test-root', 'book', 'chapter-a'),
              '未保存的草稿',
            );
        await Future<void>.delayed(Duration.zero);
        expect(container.read(saveStatusProvider), SaveStatus.unsaved);
        container.read(currentChapterProvider.notifier).state = 'chapter-b';
        expect(container.read(saveStatusProvider), SaveStatus.idle);
        container.read(currentChapterProvider.notifier).state = 'chapter-a';
        expect(container.read(saveStatusProvider), SaveStatus.unsaved);
      },
    );

    test('showSidebarProvider starts visible', () {
      final container = testContainer();
      addTearDown(container.dispose);
      expect(container.read(showSidebarProvider), isTrue);
    });

    test('showAiPanelProvider starts hidden', () {
      final container = testContainer();
      addTearDown(container.dispose);
      expect(container.read(showAiPanelProvider), isFalse);
    });

    test('showMinimapProvider starts visible', () {
      final container = testContainer();
      addTearDown(container.dispose);
      expect(container.read(showMinimapProvider), isTrue);
    });

    test('currentBookProvider starts null', () {
      final container = testContainer();
      addTearDown(container.dispose);
      expect(container.read(currentBookProvider), isNull);
    });

    test('currentChapterProvider starts null', () {
      final container = testContainer();
      addTearDown(container.dispose);
      expect(container.read(currentChapterProvider), isNull);
    });

    test('currentContentProvider returns null when no book', () {
      final container = testContainer();
      addTearDown(container.dispose);
      // currentContentProvider 是同步 Provider<String?> (非 FutureProvider)
      final result = container.read(currentContentProvider);
      expect(result, isNull);
    });

    test('appRouteProvider starts at home', () {
      final container = testContainer();
      addTearDown(container.dispose);
      expect(container.read(appRouteProvider), AppRoute.home);
    });

    test('selectedModelProvider has default', () {
      final container = testContainer();
      addTearDown(container.dispose);
      expect(container.read(selectedModelProvider), 'deepseek-v4-pro');
    });

    test('editorFontFamilyProvider starts null (system default)', () {
      final container = testContainer();
      addTearDown(container.dispose);
      expect(container.read(editorFontFamilyProvider), isNull);
    });
  });
}
