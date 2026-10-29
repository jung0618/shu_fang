import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/writing_request_ledger.dart';
import 'package:shufang_flutter/services/engine_request_status.dart';
import 'package:shufang_flutter/store/local_data_source.dart';
import 'package:shufang_flutter/theme/theme.dart';
import 'package:shufang_flutter/widgets/writing_request_history_dialog.dart';

import 'writing_request_ledger_test.dart' show requestPlan;

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('shufang-ledger-ui-');
    localDataSource.selectWorkspace(root.path, isPrimary: false);
  });
  tearDown(() async {
    localDataSource.clearUser();
    await root.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double width = 940,
    double scale = 1,
    Future<EngineRequestStatus> Function(String)? requestLookup,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var theme = brightness == Brightness.dark ? AppTheme.dark : AppTheme.light;
    final font = Platform.environment['SHUFANG_UI_FONT'];
    if (font != null) {
      final bytes = await File(font).readAsBytes();
      for (final family in ['system-ui', 'serif']) {
        await (FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      await (FontLoader('ReviewChinese')
        ..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'ReviewChinese'),
      );
    }
    final iconFont = Platform.environment['SHUFANG_UI_ICON_FONT'];
    if (iconFont != null) {
      final bytes = await File(iconFont).readAsBytes();
      await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('review'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
          home: Scaffold(
            body: WritingRequestHistoryDialog(
              root: root.path,
              requestLookup: requestLookup,
            ),
          ),
        ),
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    do {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 16));
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Request history did not settle');
      }
    } while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty);
    await tester.pumpAndSettle();
  }

  testWidgets('empty state explains scope without simulated data or action', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await mount(tester);
      expect(find.text('还没有写作调用'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'explicit query is read-only and stays separate from local failure',
    (tester) async {
      await tester.runAsync(() async {
        final run = await WritingRequestLedger.begin(
          root: root.path,
          plan: requestPlan(),
          model: 'synthetic',
          useEngine: true,
        );
        await run.dispatch();
        await run.finish('interrupted');
        var calls = 0;
        await mount(
          tester,
          requestLookup: (id) async {
            calls++;
            return EngineRequestStatus.fromJson({
              'schema_version': 1,
              'request_id': id,
              'input_sha256': 'a' * 64,
              'state': 'completed',
              'owner_is_current_instance': false,
              'retry_allowed': false,
              'settlement': 'unknown',
            }, requestId: id);
          },
        );
        expect(calls, 0);
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('核查引擎记录'));
        await tester.tap(find.text('核查引擎记录'));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(find.textContaining('引擎已收齐回复'), findsOneWidget);
        expect(find.text('本地接收已中断'), findsOneWidget);
        expect(
          (await WritingRequestLedger.read(root.path)).records.single.state,
          'interrupted',
        );
        expect(find.text('重新生成'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('query result from previous workspace is discarded', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final run = await WritingRequestLedger.begin(
        root: root.path,
        plan: requestPlan(),
        model: 'synthetic',
        useEngine: true,
      );
      await run.dispatch();
      await run.finish('failed');
      final pending = Completer<EngineRequestStatus>();
      await mount(tester, requestLookup: (_) => pending.future);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('核查引擎记录'));
      await tester.tap(find.text('核查引擎记录'));
      await tester.pump();
      localDataSource.selectWorkspace(root.path, isPrimary: false);
      pending.complete(
        EngineRequestStatus.fromJson({
          'schema_version': 1,
          'request_id': run.id,
          'input_sha256': 'a' * 64,
          'state': 'completed',
          'owner_is_current_instance': true,
          'retry_allowed': false,
          'settlement': 'unknown',
        }, requestId: run.id),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('原核查结果已丢弃'), findsOneWidget);
      expect(find.textContaining('引擎已收齐回复'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'readable ${brightness.name} receipt separates usage and settlement',
      (tester) async {
        await tester.runAsync(() async {
          final run = await WritingRequestLedger.begin(
            root: root.path,
            plan: requestPlan(),
            model: '示例模型',
            useEngine: false,
          );
          await run.dispatch();
          await run.finish(
            'completed',
            output: '模拟回复',
            receipt: {
              'model': '实际报告模型',
              'id': 'local-preview-only',
              'usage': {
                'prompt_tokens': 48,
                'completion_tokens': 12,
                'total_tokens': 60,
              },
            },
          );
          await mount(tester, brightness: brightness);
          expect(find.text('回复已收齐'), findsOneWidget);
          expect(find.textContaining('费用未知'), findsWidgets);
          expect(find.textContaining('合计 60'), findsOneWidget);
          expect(find.textContaining('¥0'), findsNothing);
          await tester.tap(find.byType(ExpansionTile));
          await tester.pumpAndSettle();
          expect(find.textContaining('实际报告模型'), findsOneWidget);
          expect(tester.takeException(), isNull);
          final output = Platform.environment['SHUFANG_REVIEW_DIR'];
          if (output != null) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('review')),
            );
            final image = await boundary.toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$output/request-history-${brightness.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          }
          await tester.pumpWidget(const SizedBox());
        });
      },
    );
  }

  testWidgets('narrow window and large Chinese text remain scrollable', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final run = await WritingRequestLedger.begin(
        root: root.path,
        plan: requestPlan(),
        model: 'm',
        useEngine: true,
      );
      await run.dispatch();
      await run.finish('failed');
      await mount(tester, width: 480, scale: 1.6);
      expect(find.text('生成未完成'), findsOneWidget);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('refresh after workspace switch clears original records', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final run = await WritingRequestLedger.begin(
        root: root.path,
        plan: requestPlan(),
        model: 'm',
        useEngine: true,
      );
      await run.dispatch();
      await run.finish('completed', output: '模拟回复');
      await mount(tester);
      expect(find.text('晚灯 / 第一章'), findsOneWidget);
      final other = await Directory('${root.path}/other').create();
      localDataSource.selectWorkspace(other.path, isPrimary: false);
      await tester.tap(find.byTooltip('刷新记录'));
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (find.text('工作区已切换，请关闭后重新查看。').evaluate().isEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Workspace switch did not settle');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
      expect(find.text('晚灯 / 第一章'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
