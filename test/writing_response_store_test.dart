import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/services/writing_context.dart';
import 'package:shufang_flutter/services/writing_request_ledger.dart';
import 'package:shufang_flutter/services/writing_response_store.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('shufang-response-');
  });
  tearDown(() async => root.delete(recursive: true));

  Future<WritingRequestRun> prepare() => WritingRequestLedger.begin(
    root: root.path,
    plan: WritingContextBuilder.build(
      request: 'synthetic private request',
      manuscript: 'synthetic original manuscript',
      budget: 4000,
      task: WritingTask.feedback,
      book: '合成作品',
      chapter: '第一章',
      sourceId: 'synthetic-source',
    ),
    model: 'synthetic-model',
    useEngine: false,
  );

  Future<WritingRequestRecord> latest() async =>
      (await WritingRequestLedger.read(root.path)).records.first;

  File response(String id) => File(
    '${root.path}${Platform.pathSeparator}.shufang'
    '${Platform.pathSeparator}responses${Platform.pathSeparator}$id.json',
  );

  Future<WritingRequestRecord> complete({
    String body = '中文与 emoji 🐈\n完整回复。',
  }) async {
    final run = await prepare();
    await run.dispatch();
    await run.finish(
      'completed',
      output: body,
      receipt: {'secret': 'no-secret'},
    );
    return latest();
  }

  Future<WritingResponseSnapshot> read(WritingRequestRecord record) =>
      WritingResponseStore.readCompleted(root: root.path, record: record);

  test('public snapshots without a body cannot be copied', () {
    expect(
      const WritingResponseSnapshot(
        availability: WritingResponseAvailability.available,
        message: 'synthetic',
      ).canCopy,
      isFalse,
    );
  });

  test(
    'Chinese and emoji survive a fresh ledger read with exact UTF16 units',
    () async {
      const body = '中文与 emoji 🐈\n完整回复。';
      final record = await complete(body: body);
      final reloaded =
          (await WritingRequestLedger.read(
            root.path,
            requestId: record.id,
          )).records.single;
      final snapshot = await read(reloaded);
      expect(snapshot.availability, WritingResponseAvailability.available);
      expect(snapshot.body, body);
      expect(snapshot.canCopy, isTrue);
      final stored =
          jsonDecode(await response(record.id).readAsString()) as Map;
      expect(stored['output_units'], body.length);
      expect(stored['unit'], 'utf-16');
      expect(stored.length, 8);
      final raw = await response(record.id).readAsString();
      expect(raw, isNot(contains('synthetic original manuscript')));
      expect(raw, isNot(contains('synthetic private request')));
      expect(raw, isNot(contains('no-secret')));
      expect(record.result['cost'], isNull);
    },
  );

  test(
    'old completed records remain missing without writing or regenerating',
    () async {
      final record = await complete();
      await response(record.id).rename('${response(record.id).path}.retained');
      final before =
          await WritingRequestLedger.directory(root.path).list().length;
      final snapshot = await read(record);
      expect(snapshot.availability, WritingResponseAvailability.missing);
      expect(snapshot.body, isNull);
      expect(snapshot.canCopy, isFalse);
      expect(await response(record.id).exists(), isFalse);
      expect(
        await WritingRequestLedger.directory(root.path).list().length,
        before,
      );
    },
  );

  for (final entry
      in <String, dynamic>{
        'workspace_root': 'different-workspace',
        'request_id': '0000000000000000-${'a' * 32}',
        'context_sha256': 'a' * 64,
        'output_sha256': 'b' * 64,
        'output_units': 1,
        'unit': 'utf-8',
        'body': '篡改后的正文',
        'schema_version': 2,
      }.entries) {
    test('rejects and preserves wrong ${entry.key}', () async {
      final record = await complete();
      final file = response(record.id);
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      data[entry.key] = entry.value;
      await file.writeAsString(jsonEncode(data), flush: true);
      final before = await file.readAsBytes();
      final snapshot = await read(record);
      expect(snapshot.availability, WritingResponseAvailability.invalid);
      expect(snapshot.body, isNull);
      expect(snapshot.canCopy, isFalse);
      expect(await file.readAsBytes(), before);
    });
  }

  test('torn sidecar is invalid and preserved', () async {
    final record = await complete();
    await response(record.id).writeAsString('{"body":');
    expect(
      (await read(record)).availability,
      WritingResponseAvailability.invalid,
    );
    expect(await response(record.id).readAsString(), '{"body":');
  });

  test(
    'rereads current journal instead of trusting a completed snapshot',
    () async {
      final record = await complete();
      final journal = File(
        '${WritingRequestLedger.directory(root.path).path}'
        '${Platform.pathSeparator}${record.id}.jsonl',
      );
      await journal.writeAsString('{torn', mode: FileMode.append);
      expect(
        (await read(record)).availability,
        WritingResponseAvailability.invalid,
      );
      expect((await journal.readAsString()).endsWith('{torn'), isTrue);
    },
  );

  test('orphan sidecar without completed journal stays unverified', () async {
    final run = await prepare();
    await run.dispatch();
    final beforeTerminal = await run.file.readAsString();
    await run.finish('completed', output: '孤立的完整正文');
    // Synthetic crash fixture: the sidecar survived, terminal append did not.
    await run.file.writeAsString(beforeTerminal, flush: true);
    final snapshot = await read(await latest());
    expect(snapshot.availability, WritingResponseAvailability.unverified);
    expect(snapshot.body, isNull);
    expect(await response(run.id).exists(), isTrue);
  });

  test(
    'exclusive creation never overwrites existing evidence or marks completed',
    () async {
      final run = await prepare();
      await run.dispatch();
      await response(run.id).parent.create();
      await response(run.id).writeAsString('preexisting evidence', flush: true);
      await expectLater(
        run.finish('completed', output: '新回复'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await response(run.id).readAsString(), 'preexisting evidence');
      final record = await latest();
      expect(record.state, 'dispatching');
      expect(
        (await read(record)).availability,
        WritingResponseAvailability.unverified,
      );
    },
  );

  test(
    'invalid transition and oversized completed body generate no sidecar',
    () async {
      final run = await prepare();
      await expectLater(
        run.finish('completed', output: '正文'),
        throwsStateError,
      );
      expect(await response(run.id).exists(), isFalse);
      await run.dispatch();
      await expectLater(
        run.finish('completed', output: ' \n\t'),
        throwsStateError,
      );
      expect(await response(run.id).exists(), isFalse);
      await expectLater(
        run.finish('completed', output: '文' * 128001),
        throwsStateError,
      );
      expect(await response(run.id).exists(), isFalse);
      expect((await latest()).state, 'dispatching');
    },
  );

  for (final state in ['failed', 'interrupted']) {
    test(
      '$state never saves a partial body or trusts server completion',
      () async {
        final run = await prepare();
        await run.dispatch();
        await run.finish(
          state,
          output: '部分正文',
          receipt: {
            'server_request': {
              'request_id': run.id,
              'input_sha256': 'a' * 64,
              'state': 'completed',
            },
          },
        );
        expect(await response(run.id).exists(), isFalse);
        expect(
          (await read(await latest())).availability,
          WritingResponseAvailability.unverified,
        );
      },
    );
  }

  test(
    'linked response file is rejected when symlinks are supported',
    () async {
      final record = await complete();
      final file = response(record.id);
      final saved = await file.rename('${file.path}.retained');
      try {
        await Link(file.path).create(saved.path);
      } on FileSystemException {
        markTestSkipped('This host does not permit symbolic links.');
        return;
      }
      expect(
        (await read(record)).availability,
        WritingResponseAvailability.invalid,
      );
      expect(await saved.exists(), isTrue);
    },
  );

  test(
    'linked .shufang is rejected before begin when symlinks are supported',
    () async {
      final target =
          await Directory(
            '${root.path}${Platform.pathSeparator}target',
          ).create();
      try {
        await Link(
          '${root.path}${Platform.pathSeparator}.shufang',
        ).create(target.path);
      } on FileSystemException {
        markTestSkipped('This host does not permit symbolic links.');
        return;
      }
      await expectLater(prepare(), throwsA(isA<FileSystemException>()));
      expect(await target.list().isEmpty, isTrue);
    },
  );
}
