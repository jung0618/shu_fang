import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Both fields come from the same disk read, never from an mtime cache.
class TextFileSnapshot {
  final String text;
  final String sha256Hex;
  TextFileSnapshot._(List<int> bytes)
    : text = utf8.decode(bytes),
      sha256Hex = sha256.convert(bytes).toString();
}

class FileVersionConflict implements Exception {
  const FileVersionConflict();
}

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
  }) => _writeText(path, text, keepPrevious: keepPrevious);

  static Future<TextFileSnapshot> readTextSnapshot(String path) async =>
      TextFileSnapshot._(await File(path).readAsBytes());

  /// Serializes the comparison with this process's other writes. External
  /// writers are checked again before rename; this is not an OS-level CAS.
  static Future<void> writeTextIfUnchanged(
    String path,
    String text, {
    required String expectedSha256,
  }) => _writeText(
    path,
    text,
    keepPrevious: true,
    expectedSha256: expectedSha256,
  );

  static Future<void> _checkVersion(File file, String expected) async {
    if (sha256.convert(await file.readAsBytes()).toString() != expected) {
      throw const FileVersionConflict();
    }
  }

  static Future<void> _writeText(
    String path,
    String text, {
    required bool keepPrevious,
    String? expectedSha256,
  }) {
    final file = File(path).absolute;
    return _enqueue(file, () async {
      List<int>? previousBytes;
      if (expectedSha256 != null) {
        previousBytes = await file.readAsBytes();
        if (sha256.convert(previousBytes).toString() != expectedSha256) {
          throw const FileVersionConflict();
        }
      } else {
        await file.parent.create(recursive: true);
        if (keepPrevious && await file.exists()) {
          previousBytes = await file.readAsBytes();
        }
      }
      if (keepPrevious && previousBytes != null) {
        final recovery = File(
          '${file.parent.path}/.recovery/${file.uri.pathSegments.last}.previous',
        );
        await recovery.parent.create(recursive: true);
        await _replaceBytes(recovery, previousBytes);
      }
      await _replaceBytes(
        file,
        utf8.encode(text),
        beforeRename:
            expectedSha256 == null
                ? null
                : () => _checkVersion(file, expectedSha256),
      );
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

  static Future<void> _replaceBytes(
    File file,
    List<int> bytes, {
    Future<void> Function()? beforeRename,
  }) async {
    final temporary = File('${file.path}.writing-$pid-${_sequence++}');
    await temporary.writeAsBytes(bytes, flush: true);
    await beforeRename?.call();
    // Same directory: no cross-volume move. Failed replacements retain the
    // temporary file for recovery rather than truncating the destination.
    await temporary.rename(file.path);
  }
}
