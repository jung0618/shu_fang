import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/chapter_save_queue.dart';
import 'package:shufang_flutter/services/editor_context_capture.dart';
import 'package:shufang_flutter/services/writing_candidate.dart';
import 'package:shufang_flutter/services/writing_context.dart';
import 'package:shufang_flutter/services/writing_goal.dart';
import 'package:shufang_flutter/services/writing_request_ledger.dart';
import 'package:shufang_flutter/store/editor_store.dart';
import 'package:shufang_flutter/store/local_data_source.dart';
import 'package:shufang_flutter/widgets/writing_candidate_preview.dart';

void main() {
  late Directory root;
  late File chapter;
  const before = '前。她放下杯子，说自己不在意。后。';
  const reply = '修改说明：用动作表现情绪。\n她放下杯子，指尖仍扣着杯沿。';
  const chosen = '她放下杯子，指尖仍扣着杯沿。😀';
  setUp(() async {
    root = await Directory.systemTemp.createTemp('shufang-preparation-');
    localDataSource.selectWorkspace(root.path, isPrimary: false);
    chapter = File('${root.path}/books/合成作品/chapters/第一章.md');
    await chapter.parent.create(recursive: true);
    await chapter.writeAsString(before);
  });
  tearDown(() async {
    localDataSource.clearUser();
    await root.delete(recursive: true);
  });

  Future<void> withPreview(
    WidgetTester tester,
    Future<void> Function(
      WritingCandidate,
      CandidateOriginWatch,
      TextEditingController,
      WidgetRef,
    )
    action, {
    WritingTask task = WritingTask.revision,
  }) async {
    await tester.runAsync(() async {
      final controller = TextEditingController(text: before)
        ..selection = const TextSelection(
          baseOffset: 2,
          extentOffset: before.length - 2,
        );
      WritingCandidate? candidate;
      CandidateOriginWatch? origin;
      late WidgetRef editorRef;
      Widget build() => ProviderScope(
        overrides: [
          currentBookProvider.overrideWith((ref) => '合成作品'),
          currentChapterProvider.overrideWith((ref) => '第一章'),
          editorControllerProvider.overrideWith(
            (ref) => (
              address: ChapterAddress(root.path, '合成作品', '第一章'),
              controller: controller,
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                editorRef = ref;
                return candidate == null
                    ? const SizedBox()
                    : WritingCandidatePreview(
                      candidate: candidate,
                      origin: origin!,
                    );
              },
            ),
          ),
        ),
      );
      try {
        await tester.pumpWidget(build());
        final source = EditorSourceSnapshot.capture(editorRef);
        origin = CandidateOriginWatch(source, controller);
        final plan = source.plan(
          request: '合成核对',
          budget: 4000,
          task: task,
          direction: await source.loadDirection(),
        );
        final run = await WritingRequestLedger.begin(
          root: root.path,
          plan: plan,
          model: 'offline-fixture',
          useEngine: false,
        );
        await run.dispatch();
        candidate =
            WritingCandidate.fromCompleted(
              source: source,
              plan: plan,
              completion: (await run.finish('completed', output: reply))!,
              body: reply,
            )!;
        await tester.pumpWidget(build());
        await waitFor(tester, find.text('整理候选正文'));
        await action(candidate, origin, controller, editorRef);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        origin?.dispose();
        controller.dispose();
      }
    });
  }

  Future<void> enterCandidate(WidgetTester tester) async {
    await tester.tap(find.text('整理候选正文'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('candidate-text'));
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.text('候选变化段'), findsNothing);
    await tester.enterText(field, chosen);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('核对并比较'));
    await tester.tap(find.text('核对并比较'));
    await waitFor(tester, find.text('候选变化段'));
  }

  for (final task in [WritingTask.revision, WritingTask.continuation]) {
    testWidgets(
      'author text stays separate and leaves manuscript untouched: ${task.name}',
      (tester) async {
        await withPreview(tester, (candidate, origin, controller, ref) async {
          final prepared = candidate.prepareText(chosen);
          expect(prepared.candidate, same(candidate));
          expect(prepared.textSha256, isNot(candidate.completion.outputSha256));
          expect(
            prepared.selectionSha256,
            WritingCandidate.fingerprint(candidate.before),
          );
          expect(candidate.body, reply);
          if (task == WritingTask.revision) {
            expect(candidate.before, '她放下杯子，说自己不在意。');
          } else {
            expect(candidate.start, before.length);
            expect(candidate.before, isEmpty);
          }
          await enterCandidate(tester);
          expect(find.text('磁盘正文与发送时正文一致（本次核对）。'), findsOneWidget);
          expect(controller.text, before);
          expect(await chapter.readAsString(), before);
          expect(ref.read(pendingInsertProvider), isNull);
          final records = await WritingRequestLedger.read(root.path);
          expect(records.records, hasLength(1));
          expect(records.records.single.state, 'completed');
          expect(
            chapterSaveQueue.draftFor(ChapterAddress(root.path, '合成作品', '第一章')),
            isNull,
          );
          final field = find.byKey(const ValueKey('candidate-text'));
          await tester.enterText(field, '$chosen 再改一字');
          await tester.pumpAndSettle();
          expect(find.text('候选变化段'), findsNothing);
          expect(
            tester
                .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                .value,
            isFalse,
          );
        }, task: task);
      },
    );
  }

  testWidgets(
    'fresh disk review detects same-mtime edits without changing cache',
    (tester) async {
      await withPreview(tester, (candidate, origin, controller, ref) async {
        expect(await localDataSource.readChapter('合成作品', '第一章'), before);
        final modified = await chapter.lastModified();
        await chapter.writeAsString('外部修改的合成文字');
        await chapter.setLastModified(modified);
        expect(await localDataSource.readChapter('合成作品', '第一章'), before);
        await enterCandidate(tester);
        expect(find.textContaining('请先核对未保存修改或外部编辑'), findsOneWidget);
        expect(await localDataSource.readChapter('合成作品', '第一章'), before);
        expect(controller.text, before);
        expect(await chapter.readAsString(), '外部修改的合成文字');
      });
    },
  );

  testWidgets('missing disk file preserves comparison and never recreates it', (
    tester,
  ) async {
    await withPreview(tester, (candidate, origin, controller, ref) async {
      await chapter.rename('${chapter.path}.held');
      await enterCandidate(tester);
      expect(find.text('暂时无法读取磁盘章节，可继续只读对照。'), findsOneWidget);
      expect(await chapter.exists(), isFalse);
    });
  });

  testWidgets('direction changed after opening blocks author comparison', (
    tester,
  ) async {
    await withPreview(tester, (candidate, origin, controller, ref) async {
      await WritingGoalStore.save(
        root: root.path,
        book: '合成作品',
        expectedVersion: null,
        target: '合成新方向',
        keep: '',
        avoid: '',
      );
      await tester.tap(find.text('整理候选正文'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('candidate-text')),
        chosen,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('核对并比较'));
      await tester.tap(find.text('核对并比较'));
      await waitFor(tester, find.textContaining('作者方向已变化'));
      expect(find.text('候选变化段'), findsNothing);
      expect(controller.text, before);
    });
  });

  testWidgets('IME and manuscript edit invalidate a prepared comparison', (
    tester,
  ) async {
    await withPreview(tester, (candidate, origin, controller, ref) async {
      await enterCandidate(tester);
      final text =
          tester
              .widget<TextField>(find.byKey(const ValueKey('candidate-text')))
              .controller!;
      text.value = text.value.copyWith(
        composing: const TextRange(start: 0, end: 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('候选变化段'), findsNothing);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      text.clearComposing();
      controller.text = '临时编辑';
      controller.text = before;
      await tester.pumpAndSettle();
      expect(find.textContaining('正文已变化'), findsOneWidget);
      expect(find.byKey(const ValueKey('candidate-text')), findsNothing);
    });
  });

  testWidgets('empty oversized or malformed author text cannot be prepared', (
    tester,
  ) async {
    await withPreview(tester, (candidate, origin, controller, ref) async {
      for (final text in [
        '',
        ' \n ',
        '甲' * 128001,
        '\ud800',
        '\udc00',
        '甲\ud800乙',
      ]) {
        expect(() => candidate.prepareText(text), throwsArgumentError);
      }
      expect(candidate.prepareText(' 甲😀𠀀\n').text, ' 甲😀𠀀\n');
      expect(controller.text, before);
    });
  });

  for (final change in ['text', 'workspace', 'close']) {
    testWidgets('late review is discarded after $change', (tester) async {
      await withPreview(tester, (candidate, origin, controller, ref) async {
        await tester.tap(find.text('整理候选正文'));
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('candidate-text'));
        await tester.enterText(field, chosen);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, '核对并比较'),
        );
        // Start the real handler, then change state before its disk awaits end.
        final pending = Function.apply(button.onPressed!, []) as Future<void>;
        if (change == 'text') {
          tester.widget<TextField>(field).controller!.text = '另一份合成候选';
        } else if (change == 'workspace') {
          localDataSource.selectWorkspace(root.path, isPrimary: false);
        } else {
          await tester.pumpWidget(const SizedBox());
        }
        await pending;
        await tester.pumpAndSettle();
        expect(find.text('候选变化段'), findsNothing);
        expect(controller.text, before);
        expect(await chapter.readAsString(), before);
      });
    });
  }

  testWidgets('explicit reply selection fills only that passage', (
    tester,
  ) async {
    await withPreview(tester, (candidate, origin, controller, ref) async {
      await tester.tap(find.text('整理候选正文'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从完整回复中选取'));
      await tester.pumpAndSettle();
      final replyWidget = tester.widget<SelectableText>(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == reply,
        ),
      );
      replyWidget.onSelectionChanged!(
        TextSelection(
          baseOffset: reply.indexOf('\n') + 1,
          extentOffset: reply.length,
        ),
        SelectionChangedCause.longPress,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('将所选文字放入候选'));
      await tester.tap(find.text('将所选文字放入候选'));
      await tester.pumpAndSettle();
      final text =
          tester
              .widget<TextField>(find.byKey(const ValueKey('candidate-text')))
              .controller!;
      expect(text.text, reply.substring(reply.indexOf('\n') + 1));
      expect(find.text('候选变化段'), findsNothing);
      expect(controller.text, before);
    });
  });
}

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Local comparison did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}
