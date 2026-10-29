import 'dart:async';
import 'package:flutter/foundation.dart';
import '../store/local_data_source.dart';
import '../store/models.dart' show SaveStatus;

/// An immutable address, captured before asynchronous work or navigation.
@immutable
class ChapterAddress {
  final String root;
  final String book;
  final String chapter;
  const ChapterAddress(this.root, this.book, this.chapter);

  @override
  bool operator ==(Object other) =>
      other is ChapterAddress &&
      root == other.root &&
      book == other.book &&
      chapter == other.chapter;
  @override
  int get hashCode => Object.hash(root, book, chapter);
}

class _Draft {
  String text;
  int revision = 0;
  int savedRevision = -1;
  SaveStatus status = SaveStatus.unsaved;
  Timer? timer;
  Future<bool>? running;
  _Draft(this.text);
}

/// Owns drafts independently of editor widgets. Failed writes remain retryable;
/// switching a tab cannot redirect a pending write to another chapter.
class ChapterSaveQueue extends ChangeNotifier {
  final Map<ChapterAddress, _Draft> _drafts = {};
  final Map<Object, Future<bool> Function()> _flushers = {};
  bool _disposed = false;
  bool _notificationPending = false;

  String? draftFor(ChapterAddress address) => _drafts[address]?.text;
  SaveStatus statusFor(ChapterAddress address) =>
      _drafts[address]?.status ?? SaveStatus.idle;

  void stage(ChapterAddress address, String text) {
    final draft = _drafts.putIfAbsent(address, () => _Draft(text));
    if (draft.text != text) {
      draft.text = text;
      draft.revision++;
    }
    draft.status =
        draft.savedRevision == draft.revision
            ? SaveStatus.saved
            : SaveStatus.unsaved;
    draft.timer?.cancel();
    draft.timer = Timer(const Duration(seconds: 2), () {
      flush(address);
    });
    _changed();
  }

  Future<bool> flush(ChapterAddress address) {
    final draft = _drafts[address];
    if (draft == null) return Future.value(true);
    draft.timer?.cancel();
    if (draft.running != null) return draft.running!;
    if (draft.savedRevision == draft.revision) return Future.value(true);
    final operation = _write(address, draft);
    draft.running = operation;
    operation.then((_) {
      draft.running = null;
    });
    return operation;
  }

  Future<bool> _write(ChapterAddress address, _Draft draft) async {
    while (draft.savedRevision != draft.revision) {
      final revision = draft.revision;
      final text = draft.text;
      draft.status = SaveStatus.saving;
      _changed();
      bool ok;
      try {
        ok = await localDataSource.writeChapter(
          address.book,
          address.chapter,
          text,
          rootOverride: address.root,
        );
      } catch (_) {
        ok = false;
      }
      if (!ok) {
        draft.status = SaveStatus.error;
        _changed();
        return false;
      }
      draft.savedRevision = revision;
    }
    draft.status = SaveStatus.saved;
    _changed();
    return true;
  }

  Future<bool> flushAll() async {
    final results = await Future.wait([
      ..._drafts.keys.toList().map(flush),
      ..._flushers.values.toList().map((flush) => flush()),
    ]);
    return results.every((ok) => ok);
  }

  void registerFlusher(Object owner, Future<bool> Function() flush) {
    _flushers[owner] = flush;
  }

  void unregisterFlusher(Object owner) => _flushers.remove(owner);

  /// Reopening a saved directory should read current disk content. Failed or
  /// active drafts remain available; this never discards an unsaved revision.
  void releaseSavedDrafts() {
    _drafts.removeWhere((address, draft) {
      if (draft.running != null || draft.savedRevision != draft.revision) {
        return false;
      }
      draft.timer?.cancel();
      return true;
    });
    _changed();
  }

  void _changed() {
    // Widgets may request a flush during disposal. Notify after that frame's
    // synchronous work, never mutate provider listeners during a build.
    if (_notificationPending || _disposed) return;
    _notificationPending = true;
    scheduleMicrotask(() {
      _notificationPending = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    for (final draft in _drafts.values) {
      draft.timer?.cancel();
    }
    super.dispose();
  }
}

final chapterSaveQueue = ChapterSaveQueue();
