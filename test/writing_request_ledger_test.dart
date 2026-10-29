import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/api/api_client.dart';
import 'package:shufang_flutter/services/direct_llm_client.dart';
import 'package:shufang_flutter/services/writing_assistant.dart';
import 'package:shufang_flutter/services/writing_context.dart';
import 'package:shufang_flutter/services/writing_request_ledger.dart';
import 'package:shufang_flutter/store/local_data_source.dart';
import 'package:shufang_flutter/store/local_prefs.dart';

WritingContextPlan requestPlan({String request = '保持沉默的张力'}) =>
    WritingContextBuilder.build(
      request: request,
      manuscript: '他没有开口，只把杯子放回桌上。',
      budget: 4000,
      task: WritingTask.feedback,
      book: '晚灯',
      chapter: '第一章',
      sourceId: 'draft-test',
    );

const reply = DirectLlmEvent(
  type: DirectLlmEventType.content,
  content: '保留这段沉默。',
);
const done = DirectLlmEvent(type: DirectLlmEventType.done);

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('shufang-ledger-');
    localDataSource.selectWorkspace(root.path, isPrimary: false);
  });
  tearDown(() async {
    localDataSource.clearUser();
    await PrefsController.update(UserPrefs.defaults);
    await root.delete(recursive: true);
  });

  Future<WritingRequestRecord> latest() async =>
      (await WritingRequestLedger.read(root.path)).records.first;

  test(
    'engine receipt keeps matching evidence only, with unknown settlement',
    () async {
      final run = await WritingRequestLedger.begin(
        root: root.path,
        plan: requestPlan(),
        model: 'synthetic',
        useEngine: true,
      );
      await run.dispatch();
      await run.finish(
        'completed',
        output: '模拟',
        receipt: {
          'server_request': {
            'request_id': run.id,
            'input_sha256': 'a' * 64,
            'state': 'completed',
            'settlement': 'paid',
            'secret': 'must-not-persist',
          },
        },
      );
      final record = await latest();
      expect(record.result['server_request'], {
        'request_id': run.id,
        'input_sha256': 'a' * 64,
        'state': 'completed',
        'settlement': 'unknown',
      });
      expect(record.result['cost'], isNull);
      expect(
        await run.file.readAsString(),
        isNot(contains('must-not-persist')),
      );
    },
  );

  test('foreign server receipt cannot attach to local request', () async {
    final run = await WritingRequestLedger.begin(
      root: root.path,
      plan: requestPlan(),
      model: 'synthetic',
      useEngine: true,
    );
    await run.dispatch();
    await run.finish(
      'failed',
      receipt: {
        'server_request': {
          'request_id': 'other',
          'input_sha256': 'a' * 64,
          'state': 'completed',
        },
      },
    );
    expect((await latest()).result.containsKey('server_request'), isFalse);
  });
  Stream<DirectLlmEvent> run(
    WritingTransport transport, {
    bool engine = true,
  }) => WritingAssistant.stream(
    plan: requestPlan(),
    model: 'test-requested-model',
    useEngine: engine,
    transportOverride: transport,
  );

  test(
    'durable dispatch precedes generation; complete precedes done; no plaintext or secrets',
    () async {
      var calls = 0;
      await for (final event in run((receipt) async* {
        calls++;
        expect((await latest()).state, 'dispatching');
        expect((await latest()).active, isTrue);
        receipt({
          'id': 'provider-1',
          'model': 'actual-model',
          'finish_reason': 'stop',
          'usage': {
            'prompt_tokens': 42,
            'completion_tokens': 9,
            'total_tokens': 51,
          },
          'api_key': 'secret-must-not-persist',
        });
        yield reply;
        yield done;
      })) {
        if (event.type == DirectLlmEventType.done) {
          expect((await latest()).state, 'completed');
        }
      }
      final record = await latest();
      expect(calls, 1);
      expect(record.meta['book'], '晚灯');
      expect(record.meta['route'], 'engine');
      expect(record.result['observed_model'], 'actual-model');
      expect(record.result['usage']['total_tokens'], 51);
      expect(record.result['cost'], isNull);
      expect(record.result['settlement'], 'unknown');
      expect(record.active, isFalse);
      final files =
          await WritingRequestLedger.directory(root.path).list().toList();
      final raw = await (files.single as File).readAsString();
      for (final text in [
        '他没有开口',
        '保持沉默的张力',
        '保留这段沉默',
        'secret-must-not-persist',
      ]) {
        expect(raw, isNot(contains(text)));
      }
    },
  );

  test(
    'context digest stable for same packet and changes with author direction',
    () async {
      Future<WritingRequestRun> begin(WritingContextPlan plan) =>
          WritingRequestLedger.begin(
            root: root.path,
            plan: plan,
            model: 'm',
            useEngine: false,
          );
      final a = await begin(requestPlan());
      await a.finish('interrupted');
      final b = await begin(requestPlan());
      await b.finish('interrupted');
      final c = await begin(requestPlan(request: '缩短动作描写'));
      await c.finish('interrupted');
      final records = (await WritingRequestLedger.read(root.path)).records;
      expect(
        records[1].meta['context_sha256'],
        records[2].meta['context_sha256'],
      );
      expect(
        records[0].meta['context_sha256'],
        isNot(records[1].meta['context_sha256']),
      );
      expect(records.map((r) => r.id).toSet().length, 3);
    },
  );

  test('missing usage stays null; provider-reported zero is preserved', () {
    expect(WritingRequestRun.providerReceipt({})['usage'], isNull);
    expect(
      WritingRequestRun.providerReceipt({
        'usage': {
          'prompt_tokens': -1,
          'total_tokens': '99',
          'completion_tokens': true,
        },
      })['usage'],
      isNull,
    );
    final receipt = WritingRequestRun.providerReceipt({
      'usage': {'completion_tokens': 0},
    });
    expect(receipt['usage'], {'completion_tokens': 0});
    expect(receipt['usage_source'], 'provider_reported');
    expect(receipt['provider_request_id'], isNull);
  });

  test('partial failure does not replay through either route', () async {
    var calls = 0;
    await expectLater(
      run((receipt) async* {
        calls++;
        yield reply;
        throw const SocketException('connection lost');
      }).toList(),
      throwsA(isA<SocketException>()),
    );
    final record = await latest();
    expect(calls, 1);
    expect(record.state, 'failed');
    expect(record.result['output_units'], reply.content.length);
    expect(record.result['usage'], isNull);
    expect(record.result['settlement'], 'unknown');
  });

  test(
    'local cancellation is interrupted, never server-cancelled or completed',
    () async {
      await for (final event in run((receipt) async* {
        yield reply;
        yield done;
      })) {
        expect(event.type, DirectLlmEventType.content);
        break;
      }
      expect((await latest()).state, 'interrupted');
      expect((await latest()).active, isFalse);
    },
  );

  for (final scenario in [
    'missing-done',
    'reasoning-only',
    'empty',
    'error-event',
  ]) {
    test('$scenario cannot become a completed reply', () async {
      await expectLater(
        run((receipt) async* {
          if (scenario == 'missing-done') {
            yield reply;
            return;
          }
          if (scenario == 'reasoning-only') {
            yield const DirectLlmEvent(
              type: DirectLlmEventType.reasoning,
              content: '思考',
            );
          }
          if (scenario == 'error-event') {
            yield const DirectLlmEvent(
              type: DirectLlmEventType.error,
              content: '服务异常',
            );
          }
          yield done;
        }).toList(),
        throwsStateError,
      );
      expect((await latest()).state, 'failed');
    });
  }

  test(
    'switch workspace keeps original evidence and rejects late reply',
    () async {
      final other = await Directory('${root.path}/other').create();
      await expectLater(
        run((receipt) async* {
          localDataSource.selectWorkspace(other.path, isPrimary: false);
          yield reply;
          yield done;
        }).toList(),
        throwsStateError,
      );
      expect((await latest()).state, 'failed');
      expect((await WritingRequestLedger.read(other.path)).records, isEmpty);
    },
  );

  test('journal unavailable blocks generation before first call', () async {
    await File('${root.path}/.shufang').writeAsString('unavailable');
    var calls = 0;
    await expectLater(
      run((receipt) async* {
        calls++;
        yield reply;
        yield done;
      }).toList(),
      throwsA(isA<FileSystemException>()),
    );
    expect(calls, 0);
  });

  test('cannot select workspace implicitly or send without it', () async {
    localDataSource.clearUser();
    var calls = 0;
    await expectLater(
      run((receipt) async* {
        calls++;
        yield done;
      }).toList(),
      throwsStateError,
    );
    expect(calls, 0);
  });

  test(
    'terminal journal failure is reported without a second provider call',
    () async {
      var calls = 0;
      await expectLater(
        run((receipt) async* {
          calls++;
          final file =
              (await WritingRequestLedger.directory(root.path).list().toList())
                      .single
                  as File;
          await file.rename('${file.path}.retained');
          await Directory(file.path).create();
          yield reply;
          yield done;
        }).toList(),
        throwsStateError,
      );
      expect(calls, 1);
    },
  );

  test(
    'pagination has no duplicates and readers leave evidence unchanged',
    () async {
      for (var i = 0; i < 5; i++) {
        await run((receipt) async* {
          yield reply;
          yield done;
        }).toList();
      }
      final files =
          await WritingRequestLedger.directory(root.path).list().toList();
      final before = {
        for (final file in files.whereType<File>())
          file.path: await file.readAsString(),
      };
      final one = await WritingRequestLedger.read(root.path, limit: 2);
      final two = await WritingRequestLedger.read(
        root.path,
        limit: 2,
        cursor: one.nextCursor,
      );
      final three = await WritingRequestLedger.read(
        root.path,
        limit: 2,
        cursor: two.nextCursor,
      );
      expect(
        [
          ...one.records,
          ...two.records,
          ...three.records,
        ].map((r) => r.id).toSet().length,
        5,
      );
      expect(three.nextCursor, isNull);
      for (final file in files.whereType<File>()) {
        expect(await file.readAsString(), before[file.path]);
      }
      await expectLater(
        WritingRequestLedger.read(root.path, limit: 0),
        throwsArgumentError,
      );
    },
  );

  test('torn final line is visible and cannot certify success', () async {
    await run((receipt) async* {
      yield reply;
      yield done;
    }).toList();
    final file =
        (await WritingRequestLedger.directory(root.path).list().toList()).single
            as File;
    await file.writeAsString('{"torn":', mode: FileMode.append);
    final original = await file.readAsString();
    final page = await WritingRequestLedger.read(root.path);
    expect(page.problems, hasLength(1));
    expect(page.records.single.statusLabel, '记录不完整');
    expect(await file.readAsString(), original);
  });

  test('foreign workspace journal is never accepted as local', () async {
    await run((receipt) async* {
      yield reply;
      yield done;
    }).toList();
    final other = await Directory('${root.path}/other').create();
    final target = await WritingRequestLedger.directory(
      other.path,
    ).create(recursive: true);
    final file =
        (await WritingRequestLedger.directory(root.path).list().toList()).single
            as File;
    await file.copy('${target.path}/${file.uri.pathSegments.last}');
    final page = await WritingRequestLedger.read(other.path);
    expect(page.records, isEmpty);
    expect(page.problems, hasLength(1));
  });

  test(
    'after restart unresolved evidence stays unresolved without mutating or replaying',
    () async {
      final dir = await WritingRequestLedger.directory(
        root.path,
      ).create(recursive: true);
      final id = '1793232000000000-${'b' * 32}';
      final file = File('${dir.path}/$id.jsonl');
      final data = {
        'workspace_root': await root.resolveSymbolicLinks(),
        'context_sha256': 'c' * 64,
        'book': '晚灯',
        'chapter': '第一章',
        'requested_model': 'm',
        'route': 'direct',
      };
      await file.writeAsString(
        [
          for (var i = 0; i < 2; i++)
            jsonEncode({
              'schema_version': 1,
              'request_id': id,
              'seq': i,
              'at': '2026-10-29T00:00:00Z',
              'state': i == 0 ? 'prepared' : 'dispatching',
              'data': i == 0 ? data : {},
            }),
        ].join('\n'),
      );
      final original = await file.readAsString();
      final record =
          (await WritingRequestLedger.read(root.path)).records.single;
      expect(record.statusLabel, '未见完成回执');
      expect(record.active, isFalse);
      expect(await file.readAsString(), original);
    },
  );

  test(
    'bound engine adapter sends Chinese JSON and keeps typed receipt separate from prose',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiClient.at(Uri.parse('http://127.0.0.1:${server.port}'));
      var calls = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        Object body;
        if (request.uri.path == '/api/auth/token') {
          body = {
            'code': 0,
            'data': {'token': 'fixture-token'},
          };
        } else if (request.uri.path == '/api/engine/capabilities') {
          body = {
            'code': 0,
            'data': {
              'product': 'shufang',
              'protocol_version': 1,
              'instance_id': 'a' * 32,
              'workspace_id': 'b' * 64,
              'workspace_root': await root.resolveSymbolicLinks(),
              'capabilities': {
                'workspace_api': {'available': true, 'reason': 'fixture'},
                'context_feedback': {'available': true, 'reason': 'fixture'},
              },
            },
          };
        } else {
          calls++;
          final input = jsonDecode(await utf8.decoder.bind(request).join());
          expect(input['model'], '中文模型');
          expect(
            input['context_packet']['messages'].last['content'],
            '保持沉默的张力',
          );
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          request.response.write(
            'data: ${jsonEncode({
              'type': 'receipt',
              'id': 'engine-fixture',
              'usage': {'total_tokens': 7},
            })}\n\n',
          );
          request.response.write(
            'data: ${jsonEncode({'type': 'content', 'content': '保留停顿'})}\n\n',
          );
          request.response.write('data: [DONE]\n\n');
          await request.response.close();
          return;
        }
        request.response.write(jsonEncode(body));
        await request.response.close();
      });
      try {
        await client.init();
        final receipt = <String, dynamic>{};
        final events =
            await client
                .ssePostEvents(
                  '/api/chat/send-context',
                  body: {
                    'model': '中文模型',
                    'context_packet': requestPlan().toPacket(),
                  },
                  requireComplete: true,
                  onReceipt: receipt.addAll,
                )
                .toList();
        expect(calls, 1);
        expect(events.map((e) => e.type), [
          SseEventType.content,
          SseEventType.done,
        ]);
        expect(receipt['usage']['total_tokens'], 7);
      } finally {
        client.close();
        await server.close(force: true);
      }
    },
  );

  test(
    'real direct SSE adapter retains usage-only final chunk with local fake provider',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var calls = 0;
      server.listen((request) async {
        calls++;
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        expect(body['model'], 'test-model');
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        for (final data in [
          {
            'id': 'fake-provider-id',
            'model': 'fake-observed-model',
            'choices': [
              {
                'delta': {'content': '本地模拟反馈'},
                'finish_reason': null,
              },
            ],
          },
          {
            'choices': [
              {'delta': {}, 'finish_reason': 'stop'},
            ],
          },
          {
            'choices': [],
            'usage': {
              'prompt_tokens': 10,
              'completion_tokens': 2,
              'total_tokens': 12,
            },
          },
        ]) {
          request.response.write('data: ${jsonEncode(data)}\n\n');
        }
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      try {
        await PrefsController.update(
          UserPrefs(
            currentProvider: 'local-fixture',
            apiProviders: {
              'local-fixture': {
                'api_key_plain': 'fake-key',
                'base_url': 'http://127.0.0.1:${server.port}',
                'default_model': 'test-model',
              },
            },
          ),
        );
        final events =
            await WritingAssistant.stream(
              plan: requestPlan(),
              model: 'test-model',
              useEngine: false,
            ).toList();
        expect(events.last.type, DirectLlmEventType.done);
        expect(calls, 1);
        final record = await latest();
        expect(record.result['usage']['total_tokens'], 12);
        expect(record.result['provider_request_id'], 'fake-provider-id');
        expect(record.result['observed_model'], 'fake-observed-model');
        expect(record.result['cost'], isNull);
      } finally {
        await server.close(force: true);
      }
    },
  );
}
