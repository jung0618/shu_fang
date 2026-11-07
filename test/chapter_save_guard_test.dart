import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/chapter_save_queue.dart';
import 'package:shufang_flutter/services/safe_file_writer.dart';
import 'package:shufang_flutter/store/editor_store.dart';
import 'package:shufang_flutter/store/local_data_source.dart';
import 'package:shufang_flutter/widgets/chapter_save_notice.dart';

void main() {
  late Directory root;
  late File file;
  late ChapterAddress address;
  late ChapterSaveQueue queue;
  late VoidCallback disposeQueue;
  const base = '合成原稿。😀\r\n第二段。';
  const edited = '合成改稿。🌙\n保留空格  ';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('shufang-save-guard-');
    address = ChapterAddress(root.path, '合成作品', '第一章');
    file = File('${root.path}/books/合成作品/chapters/第一章.md');
    await file.parent.create(recursive: true);
    await file.writeAsString(base);
    queue = ChapterSaveQueue();
    disposeQueue = queue.dispose;
  });
  tearDown(() async {
    disposeQueue();
    await SafeFileWriter.flushAll();
    await root.delete(recursive: true); // Dedicated, generated test directory.
  });

  test('loaded disk version advances after each successful save', () async {
    expect(await queue.load(address), base);
    expect(queue.statusFor(address), SaveStatus.idle);
    queue.stage(address, edited);
    expect(await queue.flush(address), isTrue);
    queue.stage(address, '$edited\n又一段');
    expect(await queue.flush(address), isTrue);
    expect(await file.readAsString(), '$edited\n又一段');
    expect(queue.statusFor(address), SaveStatus.saved);
    expect(
      await File(
        '${file.parent.path}/.recovery/第一章.md.previous',
      ).readAsString(),
      edited,
    );
  });

  test(
    'same-mtime external edit blocks save and preserves both texts',
    () async {
      await queue.load(address);
      final mtime = await file.lastModified();
      await file.writeAsString('外部修改。');
      await file.setLastModified(mtime);
      queue.stage(address, edited);
      expect(await queue.flush(address), isFalse);
      expect(queue.problemFor(address), ChapterSaveProblem.diskChanged);
      expect(await file.readAsString(), '外部修改。');
      expect(queue.draftFor(address), edited);
      expect(
        await Directory('${file.parent.path}/.recovery').exists(),
        isFalse,
      );
    },
  );

  test(
    'conflict stays latched across edits, reload and manual retry',
    () async {
      await queue.load(address);
      await file.writeAsString('外部版本');
      queue.stage(address, edited);
      await queue.flush(address);
      await file.writeAsString(base);
      queue.stage(address, '$edited 新增');
      expect(await queue.load(address), '$edited 新增');
      queue.releaseSavedDrafts();
      expect(await queue.flush(address), isFalse);
      expect(queue.statusFor(address), SaveStatus.error);
      expect(await file.readAsString(), base);
    },
  );

  test('unknown baseline cannot be acquired from a later load', () async {
    queue.stage(address, edited);
    expect(await queue.flush(address), isFalse);
    expect(queue.problemFor(address), ChapterSaveProblem.baselineMissing);
    expect(await queue.load(address), edited);
    expect(await queue.flush(address), isFalse);
    expect(await file.readAsString(), base);
  });

  test('late initial read never replaces an already staged draft', () async {
    final loading = queue.load(address);
    queue.stage(address, edited);
    expect(await loading, edited);
    expect(await queue.flush(address), isFalse);
    expect(queue.problemFor(address), ChapterSaveProblem.baselineMissing);
  });

  test('initial editor load ignores same-mtime cached content', () async {
    expect(
      await localDataSource.readChapter(
        address.book,
        address.chapter,
        rootOverride: root.path,
      ),
      base,
    );
    final mtime = await file.lastModified();
    await file.writeAsString('当前磁盘正文');
    await file.setLastModified(mtime);
    expect(await queue.load(address), '当前磁盘正文');
    queue.stage(address, edited);
    expect(await queue.flush(address), isTrue);
  });

  test(
    'missing chapter is not recreated, manual retry retains old baseline',
    () async {
      await queue.load(address);
      final parked = await file.rename('${file.path}.parked');
      queue.stage(address, edited);
      expect(await queue.flush(address), isFalse);
      expect(queue.problemFor(address), ChapterSaveProblem.unavailable);
      expect(await file.exists(), isFalse);
      expect(queue.draftFor(address), edited);
      await parked.rename(file.path);
      expect(await queue.flush(address), isTrue);
      expect(queue.problemFor(address), isNull);
    },
  );

  test(
    'active chapter provider loads the same guarded queue used for saves',
    () async {
      final container = ProviderContainer(
        overrides: [
          chapterSaveQueueProvider.overrideWith((ref) => queue),
          storageRootProvider.overrideWithValue(root.path),
        ],
      );
      disposeQueue = container.dispose;
      final subscription = container.listen(
        chapterContentProvider('${address.book}:${address.chapter}'),
        (_, __) {},
      );
      addTearDown(subscription.close);
      expect(
        await container.read(
          chapterContentProvider('${address.book}:${address.chapter}').future,
        ),
        base,
      );
      queue.stage(address, edited);
      expect(await queue.flush(address), isTrue);
      expect(await file.readAsString(), edited);
    },
  );

  test('changed BOM is detected even when visible text is identical', () async {
    await queue.load(address);
    await file.writeAsBytes([0xef, 0xbb, 0xbf, ...utf8.encode(base)]);
    queue.stage(address, edited);
    expect(await queue.flush(address), isFalse);
    expect(queue.problemFor(address), ChapterSaveProblem.diskChanged);
  });

  test('empty chapter is a valid disk baseline', () async {
    await file.writeAsString('');
    expect(await queue.load(address), '');
    queue.stage(address, edited);
    expect(await queue.flush(address), isTrue);
  });

  test('invalid UTF-8 is not accepted as an editable baseline', () async {
    await file.writeAsBytes([0xff, 0xfe]);
    expect(await queue.load(address), isNull);
    expect(queue.draftFor(address), isNull);
  });

  test('backup preserves original BOM and CRLF bytes', () async {
    final bytes = [0xef, 0xbb, 0xbf, ...utf8.encode(base)];
    await file.writeAsBytes(bytes);
    expect(await queue.load(address), base);
    queue.stage(address, edited);
    expect(await queue.flush(address), isTrue);
    expect(
      await File('${file.parent.path}/.recovery/第一章.md.previous').readAsBytes(),
      bytes,
    );
  });

  test('concurrent queues cannot both replace the same disk version', () async {
    final other = ChapterSaveQueue();
    addTearDown(other.dispose);
    await Future.wait([queue.load(address), other.load(address)]);
    queue.stage(address, edited);
    other.stage(address, '另一编辑器的合成改稿');
    final results = await Future.wait([
      queue.flush(address),
      other.flush(address),
    ]);
    expect(results.where((ok) => ok), hasLength(1));
    expect(results.where((ok) => !ok), hasLength(1));
    expect([
      queue.problemFor(address),
      other.problemFor(address),
    ], contains(ChapterSaveProblem.diskChanged));
  });

  test('edits during a save use the newly saved disk version', () async {
    await queue.load(address);
    queue.stage(address, edited);
    final saving = queue.flush(address);
    queue.stage(address, '$edited 最后修订');
    expect(await saving, isTrue);
    expect(await file.readAsString(), '$edited 最后修订');
    expect(queue.statusFor(address), SaveStatus.saved);
  });

  test('saved snapshots can be released for a fresh later load', () async {
    await queue.load(address);
    queue.stage(address, edited);
    await queue.flush(address);
    queue.releaseSavedDrafts();
    await file.writeAsString('之后的外部版本');
    expect(await queue.load(address), '之后的外部版本');
  });

  test('different root cannot redirect the pending write', () async {
    await queue.load(address);
    queue.stage(address, edited);
    final elsewhere = ChapterAddress(
      '${root.path}/other',
      address.book,
      address.chapter,
    );
    queue.stage(elsewhere, '另一工作区');
    expect(await queue.flushAll(), isFalse);
    expect(await file.readAsString(), edited);
    expect(queue.problemFor(elsewhere), ChapterSaveProblem.baselineMissing);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'conflict notice wraps and copies latest draft in $brightness',
      (tester) async {
        await tester.runAsync(() async {
          await queue.load(address);
          await file.writeAsString('外部版本');
          queue.stage(address, edited);
          await queue.flush(address);
        });
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final container = ProviderContainer(
          overrides: [chapterSaveQueueProvider.overrideWith((ref) => queue)],
        );
        disposeQueue = container.dispose;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 420,
                    child: MediaQuery(
                      data: const MediaQueryData(
                        textScaler: TextScaler.linear(1.4),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [ChapterSaveNotice(address: address)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.textContaining('已阻止覆盖'), findsOneWidget);
        queue.stage(address, '$edited 最新');
        await tester.pump();
        await tester.tap(find.text('复制当前正文'));
        await tester.pump();
        expect(copied, '$edited 最新');
        expect(queue.problemFor(address), ChapterSaveProblem.diskChanged);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
