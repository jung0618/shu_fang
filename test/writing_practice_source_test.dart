import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/chapter_save_queue.dart';
import 'package:shufang_flutter/services/direct_llm_client.dart';
import 'package:shufang_flutter/services/editor_context_capture.dart';
import 'package:shufang_flutter/services/practice_learning_view.dart';
import 'package:shufang_flutter/services/writing_assistant.dart';
import 'package:shufang_flutter/services/writing_context.dart';
import 'package:shufang_flutter/services/writing_practice.dart';
import 'package:shufang_flutter/services/writing_practice_history.dart';
import 'package:shufang_flutter/services/writing_preferences.dart';
import 'package:shufang_flutter/services/writing_request_ledger.dart';
import 'package:shufang_flutter/store/editor_store.dart';
import 'package:shufang_flutter/store/local_data_source.dart';
import 'package:shufang_flutter/widgets/practice_source_details.dart';
import 'package:shufang_flutter/widgets/practice_learning_details.dart';

import 'support/practice_fixture.dart';

const original = '他把杯子推远，又看了看门口。';
const changed = '他握着杯子，望向门口。';
String responseFor(String quote) => jsonEncode({
  'observations': [
    {
      'quote': quote,
      'observation': '动作保留迟疑',
      'reason': '贴近本次意图',
      'direction': '尝试保留停顿',
      'exercise': '自行改写一句',
      'example': '',
    },
  ],
});

void main() {
  late Directory root;
  late TextEditingController controller;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('shufang-source-');
    localDataSource.selectWorkspace(root.path, isPrimary: false);
    controller = TextEditingController(text: original)
      ..selection = const TextSelection(
        baseOffset: 0,
        extentOffset: original.length,
      );
  });
  tearDown(() async {
    controller.dispose();
    localDataSource.clearUser();
    await root.delete(recursive: true);
  });

  Future<EditorSourceSnapshot> capture(WidgetTester tester) async {
    late EditorSourceSnapshot source;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentBookProvider.overrideWith((ref) => '测试作品'),
          currentChapterProvider.overrideWith((ref) => '第一章'),
          editorControllerProvider.overrideWith(
            (ref) => (
              address: ChapterAddress(root.path, '测试作品', '第一章'),
              controller: controller,
            ),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              source = EditorSourceSnapshot.capture(ref);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return source;
  }

  WritingContextPlan plan(
    EditorSourceSnapshot source, {
    bool compare = false,
  }) => WritingPracticeContext.build(
    passage: original,
    goal: PracticeGoal.dialogue,
    intention: '保留迟疑',
    book: source.book,
    chapter: source.chapter,
    sourceId: source.id,
    budget: 4000,
    revision: compare ? changed : null,
  );

  Future<PracticeFeedbackSource> provenance(
    EditorSourceSnapshot source, {
    bool compare = false,
  }) async {
    final frozen = plan(source, compare: compare);
    final response = responseFor(compare ? '他握着杯子' : '他把杯子推远');
    WritingRequestCompletion? completion;
    await WritingAssistant.stream(
      plan: frozen,
      model: compare ? 'review-model' : 'first-model',
      useEngine: false,
      onCompleted: (value) => completion = value,
      transportOverride: (_) async* {
        yield DirectLlmEvent(
          type: DirectLlmEventType.content,
          content: response,
        );
        yield const DirectLlmEvent(type: DirectLlmEventType.done);
      },
    ).drain<void>();
    return PracticeFeedbackSource.capture(
      request: completion!,
      plan: frozen,
      response: response,
      source: source,
      goal: PracticeGoal.dialogue,
      intention: '保留迟疑',
      passage: original,
      revision: compare ? changed : null,
      feedback: PracticeFeedback.parse(response, compare ? changed : original),
    );
  }

  Future<String> save(
    EditorSourceSnapshot source,
    PracticeFeedbackSource first, {
    PracticeFeedbackSource? review,
    String revision = changed,
  }) => WritingPracticeStore.save(
    source: source,
    goal: PracticeGoal.dialogue,
    intention: '保留迟疑',
    passage: original,
    feedback: PracticeFeedback.parse(responseFor('他把杯子推远'), original),
    model: 'first-model',
    revision: revision,
    reflection: '',
    decision: 'try',
    feedbackSource: first,
    revisionFeedbackSource: review,
    revisionFeedback:
        review == null
            ? null
            : PracticeFeedback.parse(responseFor('他握着杯子'), changed),
    revisionFeedbackModel: 'review-model',
  );

  test(
    'completion is emitted after flush; failure never emits a source',
    () async {
      final frozen = WritingContextBuilder.build(
        request: '观察',
        manuscript: original,
        budget: 4000,
        task: WritingTask.feedback,
        book: '测试作品',
        chapter: '第一章',
        sourceId: 'draft-test',
      );
      WritingRequestCompletion? completed;
      await for (final event in WritingAssistant.stream(
        plan: frozen,
        model: 'm',
        useEngine: false,
        onCompleted: (value) => completed = value,
        transportOverride: (_) async* {
          yield const DirectLlmEvent(
            type: DirectLlmEventType.content,
            content: '反馈',
          );
          yield const DirectLlmEvent(type: DirectLlmEventType.done);
        },
      )) {
        if (event.type == DirectLlmEventType.done) {
          final record =
              (await WritingRequestLedger.read(
                root.path,
                requestId: completed!.requestId,
              )).records.single;
          expect(completed!.matchesRecord(record), isTrue);
        }
      }
      var called = false;
      await expectLater(
        WritingAssistant.stream(
          plan: frozen,
          model: 'm',
          useEngine: false,
          onCompleted: (_) => called = true,
          transportOverride: (_) async* {
            yield const DirectLlmEvent(
              type: DirectLlmEventType.content,
              content: '半截',
            );
          },
        ).drain<void>(),
        throwsStateError,
      );
      expect(called, isFalse);
      expect(
        (await WritingRequestLedger.read(root.path)).records.first.state,
        'failed',
      );
    },
  );

  testWidgets('separate sources round trip without creating preferences', (
    tester,
  ) async {
    final source = await capture(tester);
    await tester.runAsync(() async {
      final first = await provenance(source);
      final review = await provenance(source, compare: true);
      final path = await save(source, first, review: review);
      final data =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      final recalled = await WritingPracticeHistory.loadCase(
        root.path,
        source.book,
        data['id'],
      );
      expect(
        recalled.feedbackSource!.request.requestId,
        first.request.requestId,
      );
      expect(
        recalled.revisionFeedbackSource!.request.requestId,
        review.request.requestId,
      );
      expect(first.request.requestId, isNot(review.request.requestId));
      expect(first.reviewedSha256, isNot(review.reviewedSha256));
      final view = await PracticeLearningView.load(
        root.path,
        source.book,
        recalled.id,
      );
      expect(view.candidates.map((item) => item.hasStoredSource), [true, true]);
      expect(view.candidates.map((item) => item.fromRevision), [false, true]);
      expect(view.confirmed, isEmpty);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PracticeLearningDetails(
                root: root.path,
                book: source.book,
                caseId: recalled.id,
                preferenceVersion: 0,
                isCurrent: () => true,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('这次练笔留下了什么'));
      await tester.pump();
      final deadline = DateTime.now().add(const Duration(seconds: 6));
      while (find.byType(LinearProgressIndicator).evaluate().isNotEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Learning view did not settle');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('已保存调用关联，原记录待核对'), findsNWidgets(2));
      expect(find.textContaining('已核验'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(
        (await WritingPreferenceStore.load(root.path, source.book)).active,
        isEmpty,
      );
      expect(data['promoted_to_preference'], isFalse);
      expect(data['evidence_status'], 'author_recorded_unassessed');
      final unchanged = await File(path).readAsBytes();
      final confirmed = await WritingPreferenceStore.confirm(
        root: root.path,
        book: source.book,
        expectedVersion: 0,
        sourceCaseId: recalled.id,
        text: '争执时保留动作里的迟疑',
      );
      expect(confirmed.active.single.sourceCaseId, recalled.id);
      final revoked = await WritingPreferenceStore.revoke(
        root: root.path,
        book: source.book,
        expectedVersion: confirmed.version,
        id: confirmed.active.single.id,
      );
      expect(revoked.active, isEmpty);
      expect(await File(path).readAsBytes(), unchanged);
    });
  });

  testWidgets(
    'changed text, direction, feedback and mixed stages are rejected',
    (tester) async {
      final source = await capture(tester);
      await tester.runAsync(() async {
        final first = await provenance(source);
        final review = await provenance(source, compare: true);
        final path = await save(source, first, review: review);
        final untouched = await File(path).readAsString();
        final data = jsonDecode(untouched) as Map<String, dynamic>;
        for (final change in <Map<String, dynamic>>[
          {'passage': original.replaceFirst('门口', '窗口')},
          {'author_revision': changed.replaceFirst('门口', '窗口')},
          {'intention': '改成激烈冲突'},
          {'goal': 'scene'},
          {'model': 'other'},
          {'feedback_source': review.toJson()},
          {'revision_feedback_source': first.toJson()},
          {'revision_feedback': null},
          {
            'feedback':
                PracticeFeedback.parse(responseFor('杯子'), original).toJson(),
          },
        ]) {
          expect(
            () => WritingPracticeCase.fromJson(
              {...data, ...change},
              root: root.path,
              book: source.book,
              id: data['id'],
            ),
            throwsFormatException,
          );
        }
        await expectLater(
          save(source, first, review: review, revision: '$changed 再停一下。'),
          throwsFormatException,
        );
        expect(await File(path).readAsString(), untouched);
      });
    },
  );

  testWidgets(
    'capture rejects unparsed, wrong output and mismatched request inputs',
    (tester) async {
      final source = await capture(tester);
      await tester.runAsync(() async {
        final first = await provenance(source);
        final response = responseFor('他把杯子推远');
        for (final kind in ['output', 'parsed', 'direction']) {
          expect(
            () => PracticeFeedbackSource.capture(
              request: first.request,
              plan: plan(source),
              response: kind == 'output' ? '$response ' : response,
              source: source,
              goal: PracticeGoal.dialogue,
              intention: kind == 'direction' ? '换个方向' : '保留迟疑',
              passage: original,
              feedback: PracticeFeedback.parse(
                kind == 'parsed' ? '{"observations":[]}' : response,
                original,
              ),
            ),
            throwsFormatException,
          );
        }
      });
    },
  );

  test(
    'legacy cases retain missing sources and stay byte-for-byte unchanged',
    () async {
      for (final schema in [1, 2, 3]) {
        final file = await writePracticeFixture(root.path, schema: schema);
        final before = await file.readAsString();
        final record = await WritingPracticeHistory.loadCase(
          root.path,
          '测试作品',
          'practice-100',
        );
        expect(record.feedbackSource, isNull);
        expect(record.revisionFeedbackSource, isNull);
        expect(await file.readAsString(), before);
      }
    },
  );

  testWidgets(
    'detail checks only the referenced local request and reports missing evidence',
    (tester) async {
      final source = await capture(tester);
      final first = (await tester.runAsync(() => provenance(source)))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PracticeSourceDetails(
                title: '原稿反馈来源',
                root: root.path,
                source: first,
                isCurrent: () => true,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('原稿反馈来源'));
      await tester.pumpAndSettle();
      expect(find.textContaining(first.request.requestId), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('核对本地调用'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('与本地完成记录一致'), findsOneWidget);
      await tester.runAsync(() async {
        // A deliberate fixture move, never deletion or repair of user evidence.
        final file = File(
          '${WritingRequestLedger.directory(root.path).path}/${first.request.requestId}.jsonl',
        );
        await file.rename('${file.path}.fixture-held');
        await tester.tap(find.text('核对本地调用'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('未找到本地调用记录'), findsOneWidget);
    },
  );

  testWidgets('legacy detail has no inferred identity or verification action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeSourceDetails(
            title: '原稿反馈来源',
            root: root.path,
            source: null,
            isCurrent: () => true,
          ),
        ),
      ),
    );
    expect(find.text('来源未记录'), findsOneWidget);
    await tester.tap(find.text('原稿反馈来源'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不按时间或模型名猜测'), findsOneWidget);
    expect(find.text('核对本地调用'), findsNothing);
  });

  testWidgets(
    'altered request ID is detected by exact lookup without rewriting evidence',
    (tester) async {
      final source = await capture(tester);
      await tester.runAsync(() async {
        final first = await provenance(source);
        final other = await provenance(source, compare: true);
        final data = first.toJson();
        data['request'] = {
          ...first.request.toJson(),
          'request_id': other.request.requestId,
        };
        final altered = PracticeFeedbackSource.fromJson(data);
        final page = await WritingRequestLedger.read(
          root.path,
          requestId: altered.request.requestId,
        );
        expect(altered.request.matchesRecord(page.records.single), isFalse);
        final file = File(
          '${WritingRequestLedger.directory(root.path).path}/${first.request.requestId}.jsonl',
        );
        final before = await file.readAsString();
        final damaged = File(
          '${WritingRequestLedger.directory(root.path).path}/${other.request.requestId}.jsonl',
        );
        await damaged.writeAsString('{torn', mode: FileMode.append);
        final torn = await WritingRequestLedger.read(
          root.path,
          requestId: other.request.requestId,
        );
        expect(torn.problems, isNotEmpty);
        expect(other.request.matchesRecord(torn.records.single), isFalse);
        expect(await file.readAsString(), before);
        await expectLater(
          WritingRequestLedger.read(root.path, requestId: '../outside'),
          throwsArgumentError,
        );
      });
    },
  );

  test(
    'consumer callback failure retains completed evidence without a second dispatch',
    () async {
      var calls = 0;
      final frozen = WritingContextBuilder.build(
        request: '观察',
        manuscript: original,
        budget: 4000,
        task: WritingTask.feedback,
        book: '测试作品',
        chapter: '第一章',
        sourceId: 'draft-test',
      );
      await expectLater(
        WritingAssistant.stream(
          plan: frozen,
          model: 'm',
          useEngine: false,
          onCompleted:
              (_) => throw const FormatException('local parsing failure'),
          transportOverride: (_) async* {
            calls++;
            yield const DirectLlmEvent(
              type: DirectLlmEventType.content,
              content: '已收齐',
            );
            yield const DirectLlmEvent(type: DirectLlmEventType.done);
          },
        ).drain<void>(),
        throwsFormatException,
      );
      expect(calls, 1);
      expect(
        (await WritingRequestLedger.read(root.path)).records.single.state,
        'completed',
      );
    },
  );
}
