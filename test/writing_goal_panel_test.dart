import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/writing_goal.dart';
import 'package:shufang_flutter/widgets/writing_goal_panel.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shufang-goal-ui-');
  });
  tearDown(() async => directory.delete(recursive: true));

  testWidgets('author edits, saves, disables, and restores a book goal', (
    tester,
  ) async {
    await tester.runAsync(() async {
      tester.view.physicalSize = const Size(760, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AuthorWritingGoal? current;
      var ready = Completer<void>();
      var dirty = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WritingGoalPanel(
                root: directory.path,
                book: '测试作品',
                locked: false,
                isCurrent: () => true,
                onChanged: (goal, isReady, isDirty) {
                  current = goal;
                  dirty = isDirty;
                  if (isReady && !ready.isCompleted) ready.complete();
                },
              ),
            ),
          ),
        ),
      );
      await ready.future.timeout(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('设置作品目标'), findsOneWidget);
      await tester.tap(find.text('设置作品目标'));
      await tester.pumpAndSettle();
      expect(dirty, isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('writing-goal-target')),
        '让人物欲言又止。',
      );
      await tester.enterText(
        find.byKey(const ValueKey('writing-goal-keep')),
        '口语和短句。',
      );
      await tester.enterText(
        find.byKey(const ValueKey('writing-goal-avoid')),
        '替人物解释情绪。',
      );
      ready = Completer<void>();
      await tester.tap(find.text('保存作品目标'));
      await ready.future.timeout(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(current!.version, 1);
      expect(current!.keep, '口语和短句。');
      expect(dirty, isFalse);
      expect(find.text('保留：口语和短句。'), findsOneWidget);
      ready = Completer<void>();
      await tester.tap(find.text('停用目标'));
      await ready.future.timeout(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(current!.enabled, isFalse);
      expect(find.text('让人物欲言又止。'), findsNothing);
      ready = Completer<void>();
      await tester.tap(find.text('重新启用'));
      await ready.future.timeout(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(current!.version, 3);
      expect(current!.enabled, isTrue);
      expect(find.text('让人物欲言又止。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'bad goal file is visible and blocks use until repaired and reloaded',
    (tester) async {
      await tester.runAsync(() async {
        final file = File(
          WritingGoalStore.pathFor(root: directory.path, book: '测试作品'),
        );
        await file.parent.create(recursive: true);
        await file.writeAsString('{broken');
        var completed = Completer<void>();
        var ready = true;
        var waitForReady = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WritingGoalPanel(
                root: directory.path,
                book: '测试作品',
                locked: false,
                isCurrent: () => true,
                onChanged: (goal, isReady, dirty) {
                  ready = isReady;
                  if ((!waitForReady || isReady) && !completed.isCompleted) {
                    completed.complete();
                  }
                },
              ),
            ),
          ),
        );
        await completed.future.timeout(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(ready, isFalse);
        expect(find.textContaining('FormatException'), findsOneWidget);
        final edit = tester.widget<TextButton>(
          find.widgetWithText(TextButton, '设置作品目标'),
        );
        expect(edit.onPressed, isNull);
        // Repair the test fixture explicitly; a failed load never overwrites it.
        await file.writeAsString(
          '{"schema_version":1,"origin":"author_explicit",'
          '"book":"测试作品","version":1,"enabled":true,"target":"克制的对白",'
          '"keep":"","avoid":"","updated_at":"2026-10-26T00:00:00.000Z"}',
        );
        completed = Completer<void>();
        waitForReady = true;
        await tester.tap(find.text('重新载入目标'));
        await completed.future.timeout(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(ready, isTrue);
        expect(find.text('克制的对白'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('a switched workspace cannot save a goal through an old panel', (
    tester,
  ) async {
    await tester.runAsync(() async {
      var current = true;
      final loaded = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WritingGoalPanel(
                root: directory.path,
                book: '测试作品',
                locked: false,
                isCurrent: () => current,
                onChanged: (_, ready, __) {
                  if (ready && !loaded.isCompleted) loaded.complete();
                },
              ),
            ),
          ),
        ),
      );
      await loaded.future.timeout(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置作品目标'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('writing-goal-target')),
        '新目标',
      );
      current = false;
      await tester.ensureVisible(find.text('保存作品目标'));
      await tester.tap(find.text('保存作品目标'));
      await tester.pumpAndSettle();
      expect(find.textContaining('工作区或章节已切换'), findsOneWidget);
      await (() async {
        expect(
          await WritingGoalStore.load(root: directory.path, book: '测试作品'),
          isNull,
        );
      })();
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('frozen feedback locks goal actions at narrow widths', (
    tester,
  ) async {
    await tester.runAsync(() async {
      tester.view.physicalSize = const Size(340, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final loaded = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WritingGoalPanel(
              root: directory.path,
              book: '测试作品',
              locked: true,
              isCurrent: () => true,
              onChanged: (_, ready, __) {
                if (ready && !loaded.isCompleted) loaded.complete();
              },
            ),
          ),
        ),
      );
      await loaded.future.timeout(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '设置作品目标'))
            .onPressed,
        isNull,
      );
      expect(find.text('本次目标已固定；下次练笔可编辑作品目标。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
