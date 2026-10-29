import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';
import 'writing_context.dart';

class EditorSourceSnapshot {
  final String id;
  final String root;
  final String book;
  final String chapter;
  final String text;
  final int? selectionStart;
  final int? selectionEnd;

  EditorSourceSnapshot._(
    this.root,
    this.book,
    this.chapter,
    this.text,
    this.selectionStart,
    this.selectionEnd,
  ) : id = 'draft-${DateTime.now().microsecondsSinceEpoch}';

  factory EditorSourceSnapshot.capture(WidgetRef ref) {
    final book = ref.read(currentBookProvider) ?? '';
    final chapter = ref.read(currentChapterProvider) ?? '';
    final handle = ref.read(editorControllerProvider);
    if (book.isEmpty ||
        chapter.isEmpty ||
        handle == null ||
        handle.address.root != localDataSource.storageRoot ||
        handle.address.book != book ||
        handle.address.chapter != chapter) {
      throw StateError('请等待当前章节载入后再使用写作助手。');
    }
    final selection = handle.controller.selection;
    final text = handle.controller.text;
    final valid =
        selection.isValid &&
        !selection.isCollapsed &&
        selection.end <= text.length;
    return EditorSourceSnapshot._(
      localDataSource.storageRoot,
      book,
      chapter,
      text,
      valid ? selection.start : null,
      valid ? selection.end : null,
    );
  }

  WritingContextPlan plan({
    required String request,
    required int budget,
    WritingTask task = WritingTask.discussion,
    String instruction = '',
    List<Map<String, String>> history = const [],
  }) => WritingContextBuilder.build(
    request: request,
    manuscript: text,
    budget: budget,
    task: task,
    book: book,
    chapter: chapter,
    sourceId: id,
    selectionStart: selectionStart,
    selectionEnd: selectionEnd,
    instruction: instruction,
    history: history,
  );
}
