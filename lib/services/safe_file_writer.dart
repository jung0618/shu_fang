import 'dart:io';

/// Serializes writes to each file. The destination stays intact until the
/// sibling temporary file has been flushed. Chapters retain one prior version.
class SafeFileWriter {
  static final Map<String, Future<void>> _pending = {};
  static int _sequence = 0;

  static Future<void> flushAll() async {
    // Include writes scheduled while an earlier batch was settling.
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.values.toList());
    }
  }

  static Future<void> writeText(
    String path,
    String text, {
    bool keepPrevious = false,
  }) {
    final file = File(path).absolute;
    return _enqueue(file, () async {
      await file.parent.create(recursive: true);
      if (keepPrevious && await file.exists()) {
        final recovery = File(
          '${file.parent.path}/.recovery/${file.uri.pathSegments.last}.previous',
        );
        await recovery.parent.create(recursive: true);
        await _replace(recovery, await file.readAsString());
      }
      await _replace(file, text);
    });
  }

  static Future<void> writeBytes(String path, List<int> bytes) {
    final file = File(path).absolute;
    final snapshot = List<int>.unmodifiable(bytes);
    return _enqueue(file, () async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.writing-$pid-${_sequence++}');
      await temporary.writeAsBytes(snapshot, flush: true);
      await temporary.rename(file.path);
    });
  }

  static Future<void> _enqueue(File file, Future<void> Function() write) {
    final previous = _pending[file.path] ?? Future<void>.value();
    final operation = previous.then((_) => write());
    // A failed operation must not poison the next write to the same file.
    final settled = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _pending[file.path] = settled;
    settled.then((_) {
      if (identical(_pending[file.path], settled)) _pending.remove(file.path);
    });
    return operation;
  }

  static Future<void> _replace(File file, String text) async {
    final temporary = File('${file.path}.writing-$pid-${_sequence++}');
    await temporary.writeAsString(text, flush: true);
    // Same directory: no cross-volume move. Failed replacements retain the
    // temporary file for recovery rather than truncating the destination.
    await temporary.rename(file.path);
  }
}
