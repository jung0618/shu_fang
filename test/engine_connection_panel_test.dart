import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/engine_launcher.dart';
import 'package:shufang_flutter/widgets/engine_connection_panel.dart';

void main() {
  testWidgets(
    'connection tools fit a narrow workspace without readiness claims',
    (tester) async {
      tester.view.physicalSize = const Size(280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: EngineConnectionPanel(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('引擎尚未连接'), findsOneWidget);
      expect(find.text('启动并连接'), findsOneWidget);
      expect(find.text('检查连接'), findsOneWidget);
      expect(find.textContaining('AI 续写/建议/总结/压缩 可用'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('cached ready status without a binding never claims connected', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engineStatusProvider.overrideWith((_) => EngineStatus.ready),
        ],
        child: const MaterialApp(home: Scaffold(body: EngineConnectionPanel())),
      ),
    );
    await tester.pump();
    expect(find.text('已连接当前工作区'), findsNothing);
    expect(find.text('引擎尚未连接'), findsOneWidget);
    expect(find.text('训练启动与快照：尚未接入'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
