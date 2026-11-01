import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/writing_request_ledger.dart';
import 'package:shufang_flutter/services/writing_response_store.dart';
import 'package:shufang_flutter/store/local_data_source.dart';
import 'package:shufang_flutter/widgets/writing_response_details.dart';

import 'writing_request_ledger_test.dart' show requestPlan;

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('shufang-response-ui-');
    localDataSource.selectWorkspace(root.path, isPrimary: false);
  });
  tearDown(() async {
    localDataSource.clearUser();
    await root.delete(recursive: true);
  });

  Future<WritingRequestRecord> record() async {
    final run = await WritingRequestLedger.begin(
      root: root.path,
      plan: requestPlan(),
      model: '候选模型',
      useEngine: false,
    );
    await run.dispatch();
    await run.finish('completed', output: '候选回复正文');
    return (await WritingRequestLedger.read(
      root.path,
    )).records.firstWhere((item) => item.id == run.id);
  }

  Future<void> mount(
    WidgetTester tester,
    WritingRequestRecord item, {
    required WritingResponseLoader loader,
    double width = 420,
    double scale = 1.4,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WritingResponseDetails(
              root: root.path,
              record: item,
              loader: loader,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'lazy read displays candidate text and offers explicit copy only',
    (tester) async {
      await tester.runAsync(() async {
        final item = await record();
        var reads = 0;
        var clipboardWrites = 0;
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardWrites++;
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
        await mount(
          tester,
          item,
          loader: ({required root, required record}) async {
            reads++;
            return const WritingResponseSnapshot(
              availability: WritingResponseAvailability.available,
              body: '候选回复正文',
              message: '本机回复已读取。',
            );
          },
        );
        expect(reads, 0);
        expect(find.text('候选回复正文'), findsNothing);
        await tester.tap(find.text('查看本机回复'));
        await tester.pumpAndSettle();
        expect(reads, 1);
        expect(find.text('候选回复正文'), findsOneWidget);
        expect(find.textContaining('未写入原稿、偏好或训练资料'), findsOneWidget);
        await tester.tap(find.text('复制回复'));
        await tester.pumpAndSettle();
        expect(clipboardWrites, 1);
        expect(copied, '候选回复正文');
        expect(find.text('回复已复制'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  for (final availability in [
    WritingResponseAvailability.missing,
    WritingResponseAvailability.invalid,
    WritingResponseAvailability.unverified,
  ]) {
    testWidgets(
      '${availability.name} response stays unavailable and uncopyable',
      (tester) async {
        await tester.runAsync(() async {
          final item = await record();
          await mount(
            tester,
            item,
            loader:
                ({
                  required root,
                  required record,
                }) async => WritingResponseSnapshot(
                  availability: availability,
                  body:
                      availability == WritingResponseAvailability.missing
                          ? null
                          : '不可展示的候选文本',
                  message: switch (availability) {
                    WritingResponseAvailability.missing => '本机未保存回复正文。',
                    WritingResponseAvailability.invalid => '回复记录校验失败；原文件未更改。',
                    WritingResponseAvailability.unverified => '无法核实回复与此请求的关联。',
                    WritingResponseAvailability.available => '不可达',
                  },
                ),
          );
          await tester.tap(find.text('查看本机回复'));
          await tester.pumpAndSettle();
          expect(find.text('复制回复'), findsNothing);
          expect(find.text('不可展示的候选文本'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      },
    );
  }

  testWidgets('late read after workspace revision change is discarded', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final item = await record();
      final pending = Completer<WritingResponseSnapshot>();
      await mount(
        tester,
        item,
        loader: ({required root, required record}) => pending.future,
      );
      await tester.tap(find.text('查看本机回复'));
      await tester.pump();
      localDataSource.selectWorkspace(root.path, isPrimary: false);
      pending.complete(
        const WritingResponseSnapshot(
          availability: WritingResponseAvailability.available,
          body: '迟到的旧回复',
          message: '回复已读取。',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('迟到的旧回复'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('copy after same-root session change does not touch clipboard', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final item = await record();
      var clipboardWrites = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboardWrites++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(
        tester,
        item,
        loader:
            ({required root, required record}) async =>
                const WritingResponseSnapshot(
                  availability: WritingResponseAvailability.available,
                  body: '候选回复正文',
                  message: '本机回复已读取。',
                ),
      );
      await tester.tap(find.text('查看本机回复'));
      await tester.pumpAndSettle();
      final copy =
          tester
              .widget<TextButton>(
                find
                    .ancestor(
                      of: find.text('复制回复'),
                      matching: find.byWidgetPredicate(
                        (widget) => widget is TextButton,
                      ),
                    )
                    .first,
              )
              .onPressed!;
      localDataSource.selectWorkspace(root.path, isPrimary: false);
      copy();
      await tester.pumpAndSettle();
      expect(clipboardWrites, 0);
      expect(find.text('候选回复正文'), findsNothing);
      expect(find.textContaining('工作区或回复状态已变化'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  for (final change in ['same-root', 'other-root', 'clear']) {
    testWidgets('session $change hides a displayed selectable reply', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final item = await record();
        await mount(
          tester,
          item,
          loader:
              ({required root, required record}) async =>
                  const WritingResponseSnapshot(
                    availability: WritingResponseAvailability.available,
                    body: '切换前的候选回复',
                    message: '已读取',
                  ),
        );
        await tester.tap(find.text('查看本机回复'));
        await tester.pumpAndSettle();
        expect(find.byType(SelectableText), findsOneWidget);
        switch (change) {
          case 'same-root':
            localDataSource.selectWorkspace(root.path, isPrimary: false);
          case 'other-root':
            localDataSource.selectWorkspace(
              '${root.path}/other',
              isPrimary: false,
            );
          case 'clear':
            localDataSource.clearUser();
        }
        // Only deliver the session notification, without an action or parent
        // rebuild that could otherwise hide the stale body by coincidence.
        await tester.pumpAndSettle();
        expect(find.text('切换前的候选回复'), findsNothing);
        expect(find.byType(SelectableText), findsNothing);
        expect(find.text('复制回复'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    });
  }

  testWidgets('parent request change discards the older pending response', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final first = await record();
      final second = await record();
      final pending = Completer<WritingResponseSnapshot>();
      final hostKey = GlobalKey<_DetailsHostState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _DetailsHost(
            key: hostKey,
            details: WritingResponseDetails(
              key: const ValueKey('response'),
              root: root.path,
              record: first,
              loader: ({required root, required record}) => pending.future,
            ),
          ),
        ),
      );
      await tester.tap(find.text('查看本机回复'));
      await tester.pump();
      hostKey.currentState!.show(
        WritingResponseDetails(
          key: const ValueKey('response'),
          root: root.path,
          record: second,
          loader:
              ({required root, required record}) async =>
                  const WritingResponseSnapshot(
                    availability: WritingResponseAvailability.available,
                    body: '新请求回复',
                    message: '已读取',
                  ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看本机回复'));
      await tester.pumpAndSettle();
      pending.complete(
        const WritingResponseSnapshot(
          availability: WritingResponseAvailability.available,
          body: '迟到的旧回复',
          message: '旧回复',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('新请求回复'), findsOneWidget);
      expect(find.text('迟到的旧回复'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('loader change discards the older pending response', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final item = await record();
      final pending = Completer<WritingResponseSnapshot>();
      final hostKey = GlobalKey<_DetailsHostState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _DetailsHost(
            key: hostKey,
            details: WritingResponseDetails(
              key: const ValueKey('response'),
              root: root.path,
              record: item,
              loader: ({required root, required record}) => pending.future,
            ),
          ),
        ),
      );
      await tester.tap(find.text('查看本机回复'));
      await tester.pump();
      hostKey.currentState!.show(
        WritingResponseDetails(
          key: const ValueKey('response'),
          root: root.path,
          record: item,
          loader:
              ({required root, required record}) async =>
                  const WritingResponseSnapshot(
                    availability: WritingResponseAvailability.available,
                    body: '新读取器回复',
                    message: '已读取',
                  ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看本机回复'));
      await tester.pumpAndSettle();
      pending.complete(
        const WritingResponseSnapshot(
          availability: WritingResponseAvailability.available,
          body: '旧读取器迟到回复',
          message: '旧回复',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('新读取器回复'), findsOneWidget);
      expect(find.text('旧读取器迟到回复'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('dark response view fits 420 logical pixels at 1.4 scale', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final item = await record();
      await mount(
        tester,
        item,
        brightness: Brightness.dark,
        loader:
            ({required root, required record}) async =>
                const WritingResponseSnapshot(
                  availability: WritingResponseAvailability.available,
                  body: '这是一段用于检查窄宽暗色界面的本机候选回复。',
                  message: '已读取',
                ),
      );
      await tester.tap(find.text('查看本机回复'));
      await tester.pumpAndSettle();
      expect(find.text('这是一段用于检查窄宽暗色界面的本机候选回复。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

class _DetailsHost extends StatefulWidget {
  final WritingResponseDetails details;
  const _DetailsHost({super.key, required this.details});

  @override
  State<_DetailsHost> createState() => _DetailsHostState();
}

class _DetailsHostState extends State<_DetailsHost> {
  late WritingResponseDetails _details = widget.details;

  void show(WritingResponseDetails details) =>
      setState(() => _details = details);

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: SingleChildScrollView(child: _details));
}
