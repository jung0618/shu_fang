import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/writing_preferences.dart';
import 'package:shufang_flutter/widgets/writing_practice_history_dialog.dart';

import 'support/practice_fixture.dart';

Future<void> waitForHistory(WidgetTester tester, bool Function() ready) async {
  await tester.pump(const Duration(milliseconds: 16));
  await Future<void>.delayed(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 16));
  final deadline = DateTime.now().add(const Duration(seconds: 6));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('History UI did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp(
          'shufang-history-ui-',
        ),
  );
  tearDown(() async => directory.delete(recursive: true));

  Future<void> mount(WidgetTester tester, {bool Function()? current}) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WritingPracticeHistoryDialog(
            root: directory.path,
            book: '测试作品',
            isCurrent: current ?? () => true,
          ),
        ),
      ),
    );
    await waitForHistory(
      tester,
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
  }

  testWidgets(
    'author recalls, confirms, follows source, and revokes without editing case',
    (tester) async {
      await tester.runAsync(() async {
        final file = await writePracticeFixture(directory.path, schema: 4);
        final original = await file.readAsString();
        await mount(tester);
        await tester.tap(find.text('第一章 · 对白'));
        await tester.pumpAndSettle();
        expect(find.text('我的改稿'), findsOneWidget);
        final remember = find.text('记住一项作品偏好');
        await tester.scrollUntilVisible(
          remember,
          250,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(remember);
        await tester.pumpAndSettle();
        final confirm = find.widgetWithText(FilledButton, '确认并记住');
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        await tester.enterText(
          find.byKey(const ValueKey('preference-text')),
          '争执场景保留沉默与停顿',
        );
        await tester.pump();
        await tester.tap(confirm);
        await waitForHistory(
          tester,
          () =>
              find.byType(LinearProgressIndicator).evaluate().isEmpty &&
              find.text('确认作品偏好').evaluate().isEmpty,
        );
        await tester.tap(find.text('作品偏好'));
        await tester.pumpAndSettle();
        expect(find.text('生效中：1/8'), findsOneWidget);
        await tester.tap(find.text('查看来源练习'));
        await waitForHistory(
          tester,
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        expect(find.text('我的改稿'), findsOneWidget);
        await tester.tap(find.text('作品偏好'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('撤销偏好'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认撤销'));
        await waitForHistory(
          tester,
          () =>
              find.byType(LinearProgressIndicator).evaluate().isEmpty &&
              find.text('确认撤销').evaluate().isEmpty,
        );
        expect(find.text('生效中：0/8'), findsOneWidget);
        expect(find.text('已撤销，后续新请求不使用'), findsOneWidget);
        expect(
          (await WritingPreferenceStore.load(directory.path, '测试作品')).active,
          isEmpty,
        );
        expect(await file.readAsString(), original);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets(
    'workspace switch during confirmation prevents any preference write',
    (tester) async {
      await tester.runAsync(() async {
        await writePracticeFixture(directory.path);
        var current = true;
        await mount(tester, current: () => current);
        await tester.tap(find.text('第一章 · 对白'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('记住一项作品偏好'),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('记住一项作品偏好'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('preference-text')),
          '只在原作品生效',
        );
        await tester.pump();
        current = false;
        await tester.tap(find.text('确认并记住'));
        await tester.pumpAndSettle();
        expect(find.textContaining('工作区或作品已切换'), findsOneWidget);
        expect(
          await File(
            WritingPreferenceStore.pathFor(directory.path, '测试作品'),
          ).exists(),
          isFalse,
        );
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets(
    'corruption is visible, retry recovers, narrow layout remains usable',
    (tester) async {
      await tester.runAsync(() async {
        final file = await writePracticeFixture(directory.path);
        await file.writeAsString('{broken');
        final preferences = File(
          WritingPreferenceStore.pathFor(directory.path, '测试作品'),
        );
        await preferences.writeAsString('{broken');
        await mount(tester);
        expect(find.textContaining('作品偏好未能载入'), findsOneWidget);
        expect(find.text('以下记录未能读取，原文件保留：'), findsOneWidget);
        expect(find.textContaining('还没有练习记录'), findsNothing);
        await writePracticeFixture(directory.path);
        await preferences.writeAsString(
          '{"schema_version":1,"origin":"author_confirmed","book":"测试作品","version":0,"items":[]}',
        );
        await tester.tap(find.text('重新载入'));
        await waitForHistory(
          tester,
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        expect(find.text('第一章 · 对白'), findsOneWidget);
        expect(find.textContaining('作品偏好未能载入'), findsNothing);
        tester.view.physicalSize = const Size(340, 900);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('第一章 · 对白'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );
}
