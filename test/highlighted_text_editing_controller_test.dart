import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/store/models.dart';
import 'package:shufang_flutter/widgets/highlighted_text_editing_controller.dart';

void main() {
  const text = '甲乙丙丁';
  const mark = HighlightMark(
    id: 'highlight-1',
    color: HighlightColor.yellow,
    startOffset: 1,
    endOffset: 3,
  );

  List<TextSpan> leaves(TextSpan span) {
    final result = <TextSpan>[];
    void visit(InlineSpan node) {
      if (node is TextSpan) {
        if (node.children == null || node.children!.isEmpty) {
          result.add(node);
        } else {
          for (final child in node.children!) {
            visit(child);
          }
        }
      }
    }

    visit(span);
    return result;
  }

  void expectBodyPreserved(TextSpan span) {
    expect(leaves(span).map((part) => part.text ?? '').join(), text);
  }

  test('renders body unchanged without highlights or composition', () {
    final controller = HighlightedTextEditingController(text: text);
    addTearDown(controller.dispose);
    final span = controller.buildTextSpan(
      context: const _TestBuildContext(),
      style: const TextStyle(fontSize: 16),
      withComposing: true,
    );
    expect(span.toPlainText(), text);
    expectBodyPreserved(span);
    expect(
      leaves(span).every((part) => part.style?.decoration == null),
      isTrue,
    );
  });

  test('keeps existing highlight background', () {
    final controller = HighlightedTextEditingController(
      text: text,
      highlights: const [mark],
    );
    addTearDown(controller.dispose);
    final span = controller.buildTextSpan(
      context: const _TestBuildContext(),
      style: const TextStyle(fontSize: 16),
      withComposing: false,
    );
    expectBodyPreserved(span);
    expect(
      leaves(span).any((part) => part.style?.backgroundColor != null),
      isTrue,
    );
    expect(
      leaves(span).every((part) => part.style?.decoration == null),
      isTrue,
    );
  });

  test('underlines composition crossing a highlight boundary', () {
    final controller = HighlightedTextEditingController(
      text: text,
      highlights: const [mark],
    );
    controller.value = const TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 2, end: 4),
    );
    addTearDown(controller.dispose);
    final before = controller.value;
    final span = controller.buildTextSpan(
      context: const _TestBuildContext(),
      style: const TextStyle(fontSize: 16),
      withComposing: true,
    );
    expectBodyPreserved(span);
    expect(
      leaves(span)
          .where((part) => part.style?.decoration == TextDecoration.underline)
          .map((part) => part.text)
          .join(),
      '丙丁',
    );
    expect(controller.value, before);
  });

  test('does not underline when withComposing is false', () {
    final controller = HighlightedTextEditingController(text: text);
    controller.value = const TextEditingValue(
      text: text,
      composing: TextRange(start: 1, end: 3),
    );
    addTearDown(controller.dispose);
    final span = controller.buildTextSpan(
      context: const _TestBuildContext(),
      style: const TextStyle(),
      withComposing: false,
    );
    expect(
      leaves(span).every((part) => part.style?.decoration == null),
      isTrue,
    );
    expectBodyPreserved(span);
  });

  test('ignores invalid and collapsed composing ranges', () {
    for (final range in [
      const TextRange(start: -1, end: -1),
      const TextRange(start: 2, end: 2),
    ]) {
      final controller = HighlightedTextEditingController(text: text);
      controller.value = TextEditingValue(text: text, composing: range);
      final span = controller.buildTextSpan(
        context: const _TestBuildContext(),
        style: const TextStyle(),
        withComposing: true,
      );
      expect(
        leaves(span).every((part) => part.style?.decoration == null),
        isTrue,
      );
      expectBodyPreserved(span);
      controller.dispose();
    }
  });

  test('combines composing underline with an existing decoration', () {
    final controller = HighlightedTextEditingController(text: text);
    controller.value = const TextEditingValue(
      text: text,
      composing: TextRange(start: 1, end: 3),
    );
    addTearDown(controller.dispose);
    final span = controller.buildTextSpan(
      context: const _TestBuildContext(),
      style: const TextStyle(decoration: TextDecoration.lineThrough),
      withComposing: true,
    );
    final parts = leaves(span);
    expect(parts.map((part) => part.text), ['甲', '乙丙', '丁']);
    expect(
      parts.every(
        (part) => part.style!.decoration!.contains(TextDecoration.lineThrough),
      ),
      isTrue,
    );
    expect(
      parts[0].style!.decoration!.contains(TextDecoration.underline),
      isFalse,
    );
    expect(
      parts[1].style!.decoration!.contains(TextDecoration.underline),
      isTrue,
    );
    expect(
      parts[2].style!.decoration!.contains(TextDecoration.underline),
      isFalse,
    );
    expectBodyPreserved(span);
  });

  test(
    'underlines only composing text with no highlights and no base style',
    () {
      final controller = HighlightedTextEditingController(text: text);
      addTearDown(controller.dispose);
      controller.value = const TextEditingValue(
        text: text,
        composing: TextRange(start: 1, end: 3),
      );
      final before = controller.value;
      final span = controller.buildTextSpan(
        context: const _TestBuildContext(),
        withComposing: true,
      );
      expect(span.toPlainText(), text);
      expect(leaves(span).map((part) => part.text), ['甲', '乙丙', '丁']);
      expect(leaves(span)[0].style?.decoration, isNull);
      expect(leaves(span)[1].style?.decoration, TextDecoration.underline);
      expect(leaves(span)[2].style?.decoration, isNull);
      expect(controller.value, before);
    },
  );

  testWidgets(
    'EditableText displays a Chinese IME update without changing it',
    (tester) async {
      final controller = HighlightedTextEditingController(
        text: text,
        highlights: const [mark],
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TextField(controller: controller))),
      );
      await tester.showKeyboard(find.byType(TextField));
      const composingValue = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 2, end: 4),
      );
      tester.testTextInput.updateEditingValue(composingValue);
      await tester.pump();
      final rendered =
          tester
                  .state<EditableTextState>(find.byType(EditableText))
                  .renderEditable
                  .text!
              as TextSpan;
      expect(rendered.toPlainText(), text);
      expect(
        leaves(rendered)
            .where(
              (part) =>
                  part.style?.decoration?.contains(TextDecoration.underline) ??
                  false,
            )
            .map((part) => part.text)
            .join(),
        '丙丁',
      );
      expect(controller.value, composingValue);
      tester.testTextInput.updateEditingValue(
        composingValue.copyWith(composing: TextRange.empty),
      );
      await tester.pump();
      final committed =
          tester
                  .state<EditableTextState>(find.byType(EditableText))
                  .renderEditable
                  .text!
              as TextSpan;
      expect(committed.toPlainText(), text);
      expect(
        leaves(committed).every(
          (part) =>
              !(part.style?.decoration?.contains(TextDecoration.underline) ??
                  false),
        ),
        isTrue,
      );
      expect(controller.text, text);
    },
  );
}

class _TestBuildContext implements BuildContext {
  const _TestBuildContext();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
