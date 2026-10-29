// =============================================================================
// ShuFang — Component Widget Tests
// =============================================================================
// 验证关键组件在亮/暗主题下的渲染与状态。
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shufang_flutter/components/app_components.dart';
import 'package:shufang_flutter/theme/theme.dart';

Widget _wrap(Widget child, {Brightness? brightness}) {
  return ProviderScope(
    child: MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('BrandHeader', () {
    testWidgets('Renders default subtitle and no badge', (tester) async {
      await tester.pumpWidget(_wrap(const BrandHeader()));
      expect(find.text('书坊'), findsOneWidget);
      expect(find.text('桌面写作 IDE'), findsOneWidget);
      expect(find.text('私有版'), findsNothing);
    });

    testWidgets('Shows private badge when enabled', (tester) async {
      await tester
          .pumpWidget(_wrap(const BrandHeader(showPrivateBadge: true)));
      expect(find.text('私有版'), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('Renders icon, title, subtitle, and CTA', (tester) async {
      await tester.pumpWidget(_wrap(EmptyState(
        icon: Icons.menu_book_rounded,
        title: '空',
        subtitle: '副标题',
        actionLabel: '行动',
        onAction: () {},
      )));
      expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
      expect(find.text('空'), findsOneWidget);
      expect(find.text('副标题'), findsOneWidget);
      expect(find.text('行动'), findsOneWidget);
    });

    testWidgets('CTA callback fires', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(EmptyState(
        icon: Icons.add,
        title: 'X',
        actionLabel: 'GO',
        onAction: () => tapped = true,
      )));
      await tester.tap(find.text('GO'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });

  group('StatusDot', () {
    testWidgets('Renders dot for all status types', (tester) async {
      for (final s in AppStatus.values) {
        await tester.pumpWidget(_wrap(StatusDot(status: s)));
        expect(find.byType(StatusDot), findsOneWidget);
      }
    });
  });

  group('ToolbarIconButton', () {
    testWidgets('Renders icon and responds to tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(ToolbarIconButton(
        icon: Icons.bolt_rounded,
        onPressed: () => tapped = true,
      )));
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.bolt_rounded));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('Disabled state does not respond to tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(ToolbarIconButton(
        icon: Icons.bolt_rounded,
        onPressed: null,
      )));
      // Tap should not throw and should not toggle the variable
      await tester.tap(find.byIcon(Icons.bolt_rounded), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tapped, isFalse);
    });

    testWidgets('Active state shows primary color', (tester) async {
      await tester.pumpWidget(_wrap(ToolbarIconButton(
        icon: Icons.bolt_rounded,
        onPressed: () {},
        active: true,
      )));
      final icon = tester.widget<Icon>(find.byIcon(Icons.bolt_rounded));
      expect(icon.color, AppColors.primary);
    });
  });

  group('AiGradientContainer', () {
    testWidgets('Renders child with gradient background', (tester) async {
      await tester.pumpWidget(_wrap(const AiGradientContainer(
        child: Text('AI'),
      )));
      expect(find.text('AI'), findsOneWidget);
    });
  });

  group('GroupLabel', () {
    testWidgets('Renders uppercase text', (tester) async {
      await tester.pumpWidget(_wrap(const GroupLabel(text: 'Books')));
      // text-transform: uppercase is CSS — Flutter's Text won't apply it,
      // but we verify the text is rendered.
      expect(find.text('BOOKS'), findsOneWidget);
    });
  });

  group('SectionHeader', () {
    testWidgets('Renders icon and title', (tester) async {
      await tester.pumpWidget(_wrap(const SectionHeader(
        icon: Icons.book,
        title: 'Books',
      )));
      expect(find.byIcon(Icons.book), findsOneWidget);
      expect(find.text('Books'), findsOneWidget);
    });
  });

  group('AppCard', () {
    testWidgets('Renders child with rounded surface', (tester) async {
      await tester.pumpWidget(_wrap(AppCard(
        child: const Text('CARD'),
        onTap: () {},
      )));
      expect(find.text('CARD'), findsOneWidget);
    });
  });

  group('Light vs Dark theme', () {
    testWidgets('Same component renders correctly in both', (tester) async {
      for (final b in Brightness.values) {
        await tester.pumpWidget(_wrap(
          const BrandHeader(),
          brightness: b,
        ));
        expect(find.text('书坊'), findsOneWidget);
      }
    });
  });
}
