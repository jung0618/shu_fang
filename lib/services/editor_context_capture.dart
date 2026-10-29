import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../store/editor_store.dart';
import '../store/local_data_source.dart';
import 'writing_context.dart';
import 'writing_direction.dart';

class EditorSourceSnapshot {
  final String id;
  final String root;
  final String book;
  final String chapter;
  final String text;
  final int? selectionStart;
  final int? selectionEnd;
  final int sessionRevision;

  EditorSourceSnapshot._(
    this.root,
    this.book,
    this.chapter,
    this.text,
    this.selectionStart,
    this.selectionEnd,
  ) : id = 'draft-${DateTime.now().microsecondsSinceEpoch}',
      sessionRevision = localDataSource.sessionRevision;

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

  Future<WritingDirectionSnapshot> loadDirection() async {
    void checkWorkspace() {
      if (sessionRevision != localDataSource.sessionRevision ||
          root != localDataSource.storageRoot) {
        throw StateError('工作区已切换，原请求未发送。');
      }
    }

    checkWorkspace();
    final direction = await WritingDirectionSnapshot.load(
      root: root,
      book: book,
    );
    checkWorkspace();
    return direction;
  }

  WritingContextPlan plan({
    required String request,
    required int budget,
    WritingTask task = WritingTask.discussion,
    String instruction = '',
    List<Map<String, String>> history = const [],
    WritingDirectionSnapshot? direction,
  }) {
    if (direction != null && direction.root != root) {
      throw ArgumentError('作者方向不属于当前工作区');
    }
    return WritingContextBuilder.build(
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
      direction: direction,
    );
  }
}
