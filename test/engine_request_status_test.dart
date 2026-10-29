import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/api/api_client.dart';
import 'package:shufang_flutter/services/engine_request_status.dart';
import 'package:shufang_flutter/store/local_data_source.dart';

const id = '1234567890123456-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
Map<String, dynamic> status({String state = 'dispatching'}) => {
  'schema_version': 1,
  'request_id': id,
  'input_sha256': 'c' * 64,
  'state': state,
  'owner_is_current_instance': false,
  'retry_allowed': false,
  'settlement': 'unknown',
};

void main() {
  test(
    'pending and interrupted evidence never claims provider cancellation',
    () {
      final pending = EngineRequestStatus.fromJson(status(), requestId: id);
      expect(pending.description, contains('未见完成'));
      final stopped = EngineRequestStatus.fromJson(
        status(state: 'interrupted'),
        requestId: id,
      );
      expect(stopped.description, contains('是否停止'));
      expect(stopped.ownerIsCurrentInstance, isFalse);
    },
  );
  for (final patch in [
    {'request_id': 'other'},
    {'retry_allowed': true},
    {'settlement': 'paid'},
    {'state': 'cancelled'},
    {'input_sha256': 'invalid'},
    {'owner_is_current_instance': null},
    {'schema_version': 9},
  ]) {
    test('rejects incompatible evidence $patch', () {
      expect(
        () => EngineRequestStatus.fromJson({
          ...status(),
          ...patch,
        }, requestId: id),
        throwsFormatException,
      );
    });
  }

  group('bound local read-only transport', () {
    late Directory root;
    late HttpServer server;
    late ApiClient client;
    late List<String> calls;
    var available = true;
    var responseCode = 0;
    Completer<void>? delay;
    Completer<void>? started;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('shufang-server-status-');
      localDataSource.selectWorkspace(root.path, isPrimary: false);
      calls = [];
      available = true;
      responseCode = 0;
      delay = null;
      started = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      client = ApiClient.at(Uri.parse('http://127.0.0.1:${server.port}'));
      server.listen((request) async {
        Object reply;
        if (request.uri.path == '/api/auth/token') {
          reply = {
            'code': 0,
            'data': {'token': 'test-token'},
          };
        } else if (request.uri.path == '/api/engine/capabilities') {
          reply = {
            'code': 0,
            'data': {
              'product': 'shufang',
              'protocol_version': 1,
              'instance_id': 'a' * 32,
              'workspace_id': 'b' * 64,
              'workspace_root': root.path,
              'capabilities': {
                'workspace_api': {'available': true, 'reason': 'test'},
                'request_ledger': {'available': available, 'reason': 'test'},
              },
            },
          };
        } else {
          calls.add('${request.method} ${request.uri.path}');
          expect(request.headers.value('X-ShuFang-Token'), 'test-token');
          expect(request.headers.value('X-ShuFang-Workspace'), 'b' * 64);
          expect(request.headers.value('X-ShuFang-Instance'), 'a' * 32);
          started?.complete();
          if (delay != null) await delay!.future;
          reply = {
            'code': responseCode,
            'data': responseCode == 0 ? status() : null,
          };
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(reply));
        await request.response.close();
      });
    });
    tearDown(() async {
      client.close();
      localDataSource.clearUser();
      await server.close(force: true);
      await root.delete(recursive: true);
    });

    test('one GET only; never uses a generation or replay route', () async {
      await client.init();
      final result = await EngineRequestStatus.lookup(id, client: client);
      expect(result.state, 'dispatching');
      expect(calls, ['GET /api/engine/requests/$id']);
    });
    test('old engines cannot receive a query', () async {
      available = false;
      await client.init();
      await expectLater(
        EngineRequestStatus.lookup(id, client: client),
        throwsStateError,
      );
      expect(calls, isEmpty);
    });
    test('missing record does not imply no request or zero fee', () async {
      responseCode = 404;
      await client.init();
      await expectLater(
        EngineRequestStatus.lookup(id, client: client),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('不能证明'),
          ),
        ),
      );
      expect(calls.length, 1);
    });
    test('workspace switch discards a late status reply', () async {
      await client.init();
      started = Completer<void>();
      delay = Completer<void>();
      final pending = EngineRequestStatus.lookup(id, client: client);
      final assertion = expectLater(pending, throwsStateError);
      await started!.future;
      localDataSource.selectWorkspace(root.path, isPrimary: false);
      delay!.complete();
      await assertion;
      expect(calls.length, 1);
    });
    test('reconnection also discards a late status reply', () async {
      await client.init();
      started = Completer<void>();
      delay = Completer<void>();
      final pending = EngineRequestStatus.lookup(id, client: client);
      final assertion = expectLater(pending, throwsStateError);
      await started!.future;
      await client.init();
      delay!.complete();
      await assertion;
    });
  });
}
