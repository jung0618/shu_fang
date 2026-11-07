// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shufang_flutter/app.dart';
import 'package:shufang_flutter/store/workspace_store.dart';

void main() {
  testWidgets('App renders without error', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [workspaceCatalogProvider.overrideWith((ref) async => [])],
        child: const ShuFangApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify the app renders (check for title or key widget)
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('打开本机工作区'), findsOneWidget);
    expect(find.text('创建并开始写作'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
