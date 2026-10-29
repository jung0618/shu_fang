import 'dart:io';

import '../store/local_data_source.dart';
import 'chapter_save_queue.dart';
import 'safe_file_writer.dart';
import 'storage_paths.dart';

enum LocalExportFormat { txt, markdown }

class BookExportSnapshot {
  final String root;
  final String book;
  final String title;
  final List<String> chapters;
  const BookExportSnapshot({
    required this.root,
    required this.book,
    required this.title,
    required this.chapters,
  });

  String render(LocalExportFormat format) {
    final titleLine = format == LocalExportFormat.markdown ? '# $title' : title;
    // Preserve the chapter source, including punctuation and paragraph breaks.
    // TXT changes the container only; it does not strip Markdown from the draft.
    return '$titleLine\n\n${chapters.join('\n\n')}\n';
  }
}

class LocalBookExporter {
  static Future<BookExportSnapshot> capture({
    required String root,
    required String book,
    required int sessionRevision,
  }) async {
    void checkSession() {
      if (sessionRevision != localDataSource.sessionRevision) {
        throw StateError('工作区已切换，请在当前工作区重新导出。');
      }
    }

    checkSession();
    if (!StoragePaths.validName(book)) throw const FormatException('作品名称无效。');
    final chapters = await localDataSource.listChapters(
      book,
      rootOverride: root,
    );
    checkSession();
    if (chapters.isEmpty) throw StateError('这部作品还没有可导出的章节。');
    final manifest = await localDataSource.readBookManifest(
      book,
      rootOverride: root,
    );
    checkSession();
    // Take copies of open drafts before awaiting file reads. Later typing is
    // outside this export snapshot and will be included in the next export.
    final drafts = {
      for (final chapter in chapters)
        chapter.id: chapterSaveQueue.draftFor(
          ChapterAddress(root, book, chapter.id),
        ),
    };
    final texts = <String>[];
    for (final chapter in chapters) {
      final text =
          drafts[chapter.id] ??
          await File(
            '$root/books/$book/chapters/${chapter.id}.md',
          ).readAsString();
      checkSession();
      texts.add(text);
    }
    final name = manifest['name'];
    return BookExportSnapshot(
      root: root,
      book: book,
      title: name is String && name.trim().isNotEmpty ? name.trim() : book,
      chapters: List.unmodifiable(texts),
    );
  }

  static Future<String> save(
    BookExportSnapshot snapshot,
    LocalExportFormat format, {
    required int sessionRevision,
  }) async {
    if (sessionRevision != localDataSource.sessionRevision) {
      throw StateError('工作区已切换，导出已停止。');
    }
    final extension = format == LocalExportFormat.txt ? 'txt' : 'md';
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final path = '${snapshot.root}/exports/${snapshot.book}-$stamp.$extension';
    await SafeFileWriter.writeText(path, snapshot.render(format));
    return File(path).absolute.path;
  }
}
