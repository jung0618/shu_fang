import 'dart:io';

import 'chapter_save_queue.dart';
import 'storage_paths.dart';

class ChapterPreviousVersion {
  final ChapterAddress address;
  final String text;
  final DateTime capturedAt;
  const ChapterPreviousVersion(this.address, this.text, this.capturedAt);
}

class ChapterRecovery {
  static Future<ChapterPreviousVersion?> readPrevious(
    ChapterAddress address,
  ) async {
    if (!StoragePaths.validName(address.book) ||
        !StoragePaths.validName(address.chapter)) {
      throw const FormatException('章节地址无效。');
    }
    final file = File(
      '${address.root}/books/${address.book}/chapters/.recovery/${address.chapter}.md.previous',
    );
    if (!await file.exists()) return null;
    final stat = await file.stat();
    final text = await file.readAsString();
    return ChapterPreviousVersion(address, text, stat.modified);
  }
}
