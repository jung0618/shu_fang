import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../store/editor_store.dart'
    show currentBookProvider, currentChapterProvider;
import '../store/local_data_source.dart';

/// Capture before awaiting. A result belongs only to this editor session.
class EditorRequestLease {
  final WidgetRef ref;
  final int revision;
  final String? book;
  final String? chapter;

  EditorRequestLease(this.ref)
    : revision = localDataSource.sessionRevision,
      book = ref.read(currentBookProvider),
      chapter = ref.read(currentChapterProvider);

  bool get isCurrent =>
      ref.context.mounted &&
      revision == localDataSource.sessionRevision &&
      book == ref.read(currentBookProvider) &&
      chapter == ref.read(currentChapterProvider);
}
