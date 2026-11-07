import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'writing_request_ledger.dart';

enum WritingResponseAvailability { available, missing, unverified, invalid }

class WritingResponseSnapshot {
  final WritingResponseAvailability availability;
  final String? body;
  final String message;

  const WritingResponseSnapshot({
    required this.availability,
    this.body,
    required this.message,
  });

  bool get canCopy =>
      availability == WritingResponseAvailability.available &&
      body != null &&
      body!.isNotEmpty;
}

/// Read-only recovery of a complete local reply. Neither server state nor a
/// sidecar alone is evidence of a locally completed request.
class WritingResponseStore {
  static Future<WritingResponseSnapshot> readCompleted({
    required String root,
    required WritingRequestRecord record,
  }) async {
    const invalid = WritingResponseSnapshot(
      availability: WritingResponseAvailability.invalid,
      message: '本机回复或调用记录校验失败，原文件已保留。',
    );
    const unverified = WritingResponseSnapshot(
      availability: WritingResponseAvailability.unverified,
      message: '未能核实完整的本地完成记录，不能恢复正文。',
    );
    try {
      if (!RegExp(r'^\d{16}-[a-f0-9]{32}$').hasMatch(record.id) ||
          record.damaged) {
        return invalid;
      }
      final canonicalRoot = await Directory(root).resolveSymbolicLinks();
      if (await WritingRequestLedger.localEvidenceDirectory(root, 'requests') ==
          null) {
        return unverified;
      }
      final page = await WritingRequestLedger.read(
        canonicalRoot,
        requestId: record.id,
      );
      if (page.problems.isNotEmpty) return invalid;
      if (page.records.length != 1) return unverified;
      final current = page.records.single;
      if (current.damaged) return invalid;
      if (current.state != 'completed' || record.state != 'completed') {
        return unverified;
      }
      // A stale selection cannot silently resolve to a different local record.
      if (jsonEncode(record.events) != jsonEncode(current.events)) {
        return unverified;
      }
      final units = current.result['output_units'];
      final outputHash = current.result['output_sha256'];
      final contextHash = current.meta['context_sha256'];
      final hashPattern = RegExp(r'^[a-f0-9]{64}$');
      if (current.meta['workspace_root'] != canonicalRoot ||
          current.meta['unit'] != 'utf-16' ||
          units is! int ||
          units < 1 ||
          units > 128000 ||
          outputHash is! String ||
          !hashPattern.hasMatch(outputHash) ||
          contextHash is! String ||
          !hashPattern.hasMatch(contextHash)) {
        return invalid;
      }
      final dir = await WritingRequestLedger.localEvidenceDirectory(
        root,
        'responses',
      );
      const missing = WritingResponseSnapshot(
        availability: WritingResponseAvailability.missing,
        message: '此调用没有可恢复的本机完整正文；旧记录不会自动补写。',
      );
      if (dir == null) return missing;
      final file = File(
        '${dir.path}${Platform.pathSeparator}${current.id}.json',
      );
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return missing;
      if (type != FileSystemEntityType.file ||
          await file.resolveSymbolicLinks() != file.path ||
          await file.length() > 1024 * 1024) {
        return invalid;
      }
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic> ||
          data.length != 8 ||
          data['schema_version'] != 1 ||
          data['workspace_root'] != canonicalRoot ||
          data['request_id'] != current.id ||
          data['context_sha256'] != contextHash ||
          data['output_sha256'] != outputHash ||
          data['output_units'] != units ||
          data['unit'] != 'utf-16' ||
          data['body'] is! String) {
        return invalid;
      }
      final body = data['body'] as String;
      if (body.length != units ||
          sha256.convert(utf8.encode(body)).toString() != outputHash) {
        return invalid;
      }
      // A journal may be appended while the sidecar is being read. A changed
      // or newly damaged journal must invalidate this recovery attempt.
      final verified = await WritingRequestLedger.read(
        canonicalRoot,
        requestId: current.id,
      );
      await WritingRequestLedger.localEvidenceDirectory(root, 'requests');
      await WritingRequestLedger.localEvidenceDirectory(root, 'responses');
      if (verified.problems.isNotEmpty) return invalid;
      if (verified.records.length != 1 ||
          verified.records.single.damaged ||
          jsonEncode(verified.records.single.events) !=
              jsonEncode(current.events)) {
        return unverified;
      }
      return WritingResponseSnapshot(
        availability: WritingResponseAvailability.available,
        body: body,
        message: '已校验本机完整回复。',
      );
    } catch (_) {
      return invalid;
    }
  }
}
