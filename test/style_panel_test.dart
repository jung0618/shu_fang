import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/api/api_client.dart';
import 'package:shufang_flutter/widgets/style_panel.dart';

Future<void> showPanel(
  WidgetTester tester,
  Future<ApiResponse> Function() loader, {
  double width = 360,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 700,
          child: StylePanel(profileLoader: loader),
        ),
      ),
    ),
  );
  await tester.tap(find.text('刷新画像'));
  await tester.pumpAndSettle();
}

Map<String, dynamic> fixture() => {
  'meta': {'sample_count': 2},
  'dimensions': {
    'avg_sentence_length': {'value': 24.8},
    'dialogue_ratio': {'value': .35},
    'paragraph_length_avg': {'value': 88.0},
  },
  'training': {
    'style_reference': {
      'available': true,
      'sample_count': 39,
      'schemas': [
        {
          'schema': 'legacy_style_features',
          'label': '旧引擎参考',
          'sample_count': 29,
          'dimensions': {
            'sentences_per_paragraph': {'value': 2.5, 'samples': 29},
            'dialogue_ratio': {'value': .22, 'samples': 29},
          },
        },
        {
          'schema': 'modern_features',
          'label': '新版特征参考',
          'sample_count': 10,
          'dimensions': {
            'paragraph_length_avg': {'value': 80, 'samples': 10},
          },
        },
      ],
      'sources': [
        {'label': 'legacy-cdm', 'sample_count': 29},
        {'label': 'private-data', 'sample_count': 10},
      ],
    },
  },
};

void main() {
  testWidgets('actual metric objects use distinct units and reference groups', (
    tester,
  ) async {
    await showPanel(tester, () async => ApiResponse(code: 0, data: fixture()));
    expect(find.text('平均句长 24.8 字/句'), findsOneWidget);
    expect(find.text('对话字数占比 35.0%'), findsOneWidget);
    expect(find.text('平均段长 88.0 字/段'), findsOneWidget);
    expect(find.text('总计 39 份参考样本'), findsOneWidget);
    expect(find.text('每段句数 2.5 句/段'), findsOneWidget);
    expect(find.text('对话句占比 22.0%'), findsOneWidget);
    expect(find.text('旧引擎参考'), findsOneWidget);
    expect(find.text('新版特征参考'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no finalized samples hides default zeros', (tester) async {
    await showPanel(
      tester,
      () async => const ApiResponse(
        code: 0,
        data: {
          'meta': {'sample_count': 0},
          'dimensions': {
            'avg_sentence_length': {'value': 0.0},
          },
        },
      ),
    );
    expect(find.textContaining('尚无定档样本'), findsOneWidget);
    expect(find.textContaining('平均句长'), findsNothing);
  });

  testWidgets('malformed nested data and nonfinite values stay safe', (
    tester,
  ) async {
    await showPanel(
      tester,
      () async => ApiResponse(
        code: 0,
        data: {
          'meta': {'sample_count': 1},
          'dimensions': {
            'avg_sentence_length': {'value': double.nan},
            'dialogue_ratio': {'value': 99},
            'paragraph_length_avg': 'bad',
          },
          'training': ['broken'],
        },
      ),
    );
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('9900'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow panel scrolls without truncating numeric metrics', (
    tester,
  ) async {
    await showPanel(
      tester,
      () async => ApiResponse(code: 0, data: fixture()),
      width: 260,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('每段句数 2.5 句/段'), findsOneWidget);
  });

  testWidgets('offline state exposes retry and real error', (tester) async {
    await showPanel(tester, () async => throw StateError('offline fixture'));
    expect(find.text('服务未连接，启动本机学习服务后可刷新'), findsOneWidget);
    expect(find.textContaining('offline fixture'), findsOneWidget);
    expect(find.text('刷新画像'), findsOneWidget);
  });

  testWidgets('completion after disposal does not call setState', (
    tester,
  ) async {
    final pending = Completer<ApiResponse>();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 600,
          child: StylePanel(profileLoader: () => pending.future),
        ),
      ),
    );
    await tester.tap(find.text('刷新画像'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(const ApiResponse(code: 0, data: {}));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
