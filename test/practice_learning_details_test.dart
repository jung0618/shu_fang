import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/practice_learning_view.dart';
import 'package:shufang_flutter/services/writing_preferences.dart';
import 'package:shufang_flutter/widgets/practice_learning_details.dart';

import 'support/practice_fixture.dart';
import 'writing_practice_history_dialog_test.dart' show waitForHistory;

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shufang-learning-ui-');
    await writePracticeFixture(directory.path, schema: 4);
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<void> settled(WidgetTester tester) => waitForHistory(
    tester,
    () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
  );

  Future<void> mount(
    WidgetTester tester, {
    bool Function()? current,
    int? version,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PracticeLearningDetails(
              root: directory.path,
              book: '测试作品',
              caseId: 'practice-100',
              preferenceVersion: version,
              isCurrent: current ?? () => true,
            ),
          ),
        ),
      ),
    );
    await settled(tester);
  }

  testWidgets(
    'lazy local review refreshes revocation without rewriting the case',
    (tester) async {
      await tester.runAsync(() async {
        final file = File(
          PracticePaths.casePath(directory.path, '测试作品', 'practice-100'),
        );
        final before = await file.readAsBytes();
        final preferences = await WritingPreferenceStore.confirm(
          root: directory.path,
          book: '测试作品',
          expectedVersion: 0,
          sourceCaseId: 'practice-100',
          text: '保留沉默',
        );
        await mount(tester);
        expect(find.text('保留沉默'), findsNothing);
        await tester.tap(find.text('这次练笔留下了什么'));
        await settled(tester);
        expect(find.text('保留沉默'), findsOneWidget);
        expect(find.textContaining('尚不代表确认长期偏好'), findsOneWidget);
        expect(find.textContaining('未记录调用关联'), findsOneWidget);
        await WritingPreferenceStore.revoke(
          root: directory.path,
          book: '测试作品',
          expectedVersion: 1,
          id: preferences.active.single.id,
        );
        await tester.ensureVisible(find.text('重新核对复盘'));
        await tester.tap(find.text('重新核对复盘'));
        await settled(tester);
        expect(find.text('已撤销，仅供回看'), findsOneWidget);
        expect(find.textContaining('当前没有生效项'), findsOneWidget);
        expect(find.textContaining('偏好版本 2'), findsOneWidget);
        expect(await file.readAsBytes(), before);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets(
    'damaged store is visible and refresh recovers without model calls',
    (tester) async {
      await tester.runAsync(() async {
        final file = File(
          WritingPreferenceStore.pathFor(directory.path, '测试作品'),
        );
        await file.writeAsString('{broken');
        await mount(tester);
        await tester.tap(find.text('这次练笔留下了什么'));
        await settled(tester);
        expect(find.textContaining('本次复盘未能核对'), findsOneWidget);
        expect(find.textContaining('偏好版本'), findsNothing);
        expect(await file.readAsString(), '{broken');
        await file.writeAsString(
          '{"schema_version":1,"origin":"author_confirmed","book":"测试作品","version":0,"items":[]}',
        );
        await tester.tap(find.text('重新核对复盘'));
        await settled(tester);
        expect(find.textContaining('本次复盘未能核对'), findsNothing);
        expect(find.textContaining('偏好版本 0'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('workspace switch discards the pending local result', (
    tester,
  ) async {
    await tester.runAsync(() async {
      var current = true;
      await mount(tester, current: () => current);
      await tester.tap(find.text('这次练笔留下了什么'));
      current = false;
      await settled(tester);
      expect(find.textContaining('工作区或作品已切换'), findsOneWidget);
      expect(find.textContaining('偏好版本'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('parent preference updates invalidate an expanded review', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await mount(tester, version: 0);
      await tester.tap(find.text('这次练笔留下了什么'));
      await settled(tester);
      await WritingPreferenceStore.confirm(
        root: directory.path,
        book: '测试作品',
        expectedVersion: 0,
        sourceCaseId: 'practice-100',
        text: '明确确认后的新偏好',
      );
      await mount(tester, version: 1);
      await settled(tester);
      expect(find.text('明确确认后的新偏好'), findsOneWidget);
      expect(find.textContaining('偏好版本 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'an older pending result cannot replace a newer revoked snapshot',
    (tester) async {
      await tester.runAsync(() async {
        final first = await WritingPreferenceStore.confirm(
          root: directory.path,
          book: '测试作品',
          expectedVersion: 0,
          sourceCaseId: 'practice-100',
          text: '已经撤销的旧选择',
        );
        final oldView = await PracticeLearningView.load(
          directory.path,
          '测试作品',
          'practice-100',
        );
        await WritingPreferenceStore.revoke(
          root: directory.path,
          book: '测试作品',
          expectedVersion: 1,
          id: first.active.single.id,
        );
        final newView = await PracticeLearningView.load(
          directory.path,
          '测试作品',
          'practice-100',
        );
        final older = Completer<PracticeLearningView>();
        final newer = Completer<PracticeLearningView>();
        var calls = 0;
        Future<PracticeLearningView> loader(
          String root,
          String book,
          String id,
        ) => ++calls == 1 ? older.future : newer.future;
        Future<void> show(int version) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PracticeLearningDetails(
                  root: directory.path,
                  book: '测试作品',
                  caseId: 'practice-100',
                  preferenceVersion: version,
                  isCurrent: () => true,
                  loadView: loader,
                ),
              ),
            ),
          ),
        );
        await show(1);
        await tester.tap(find.text('这次练笔留下了什么'));
        await tester.pump();
        expect(calls, 1);
        await show(2);
        expect(calls, 2);
        newer.complete(newView);
        await settled(tester);
        expect(find.textContaining('偏好版本 2'), findsOneWidget);
        older.complete(oldView);
        await settled(tester);
        expect(find.textContaining('偏好版本 1'), findsNothing);
        expect(find.textContaining('当前没有生效项'), findsOneWidget);
        expect(find.text('已撤销，仅供回看'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );
}
