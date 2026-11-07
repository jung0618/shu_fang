import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shufang_flutter/api/api_client.dart';
import 'package:shufang_flutter/api/engine_capabilities.dart';
import 'package:shufang_flutter/services/engine_config.dart';
import 'package:shufang_flutter/store/local_data_source.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  late ApiClient client;
  late Map<String, dynamic> identity;
  late List<String> operations;
  Future<void> Function(HttpRequest)? intercept;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shufang-engine-');
    localDataSource.selectWorkspace(directory.path, isPrimary: false);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = ApiClient.at(Uri.parse('http://127.0.0.1:${server.port}'));
    operations = [];
    intercept = null;
    identity = {
      'product': 'shufang',
      'protocol_version': 1,
      'instance_id': 'a' * 32,
      'workspace_id': 'b' * 64,
      'workspace_root': await directory.resolveSymbolicLinks(),
      'capabilities': {
        'workspace_api': {'available': true, 'reason': 'configured'},
        'context_feedback': {'available': true, 'reason': 'route_available'},
        'training_start': {'available': false, 'reason': 'not_implemented'},
      },
    };
    server.listen((request) async {
      if (intercept != null) return intercept!(request);
      final path = request.uri.path;
      Object reply;
      if (path == '/api/auth/token') {
        reply = {
          'code': 0,
          'data': {'token': 'test-token'},
        };
      } else if (path == '/api/engine/capabilities') {
        expect(request.headers.value('X-ShuFang-Token'), 'test-token');
        reply = {'code': 0, 'data': identity};
      } else if (path == '/api/ping') {
        reply = {'status': 'ok'};
      } else {
        expect(request.headers.value('X-ShuFang-Token'), 'test-token');
        expect(
          request.headers.value('X-ShuFang-Workspace'),
          identity['workspace_id'],
        );
        expect(
          request.headers.value('X-ShuFang-Instance'),
          identity['instance_id'],
        );
        operations.add(path);
        reply = {
          'code': 0,
          'data': {'ok': true},
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
    await directory.delete(recursive: true);
  });

  test(
    'health is not binding; non-primary workspace binds only after auth',
    () async {
      expect(await client.ping(), isTrue);
      expect(client.canUseWorkspace, isFalse);
      await expectLater(client.get('/api/books'), throwsStateError);
      await client.init();
      expect(client.supports('context_feedback'), isTrue);
      expect(client.supports('training_start'), isFalse);
      expect((await client.get('/api/books')).ok, isTrue);
      expect(operations, ['/api/books']);
    },
  );

  test(
    'foreign workspace with same book names never receives an operation',
    () async {
      final other = await Directory('${directory.path}/other').create();
      identity['workspace_root'] = other.path;
      await expectLater(client.init(), throwsStateError);
      await expectLater(client.post('/api/books/same-name'), throwsStateError);
      expect(operations, isEmpty);
    },
  );

  test(
    'workspace switch including reopening same root invalidates binding',
    () async {
      await client.init();
      localDataSource.selectWorkspace(directory.path, isPrimary: true);
      expect(client.canUseWorkspace, isFalse);
      expect(client.capabilities, isNull);
      await expectLater(client.put('/api/write'), throwsStateError);
      await client.init();
      expect(client.canUseWorkspace, isTrue);
    },
  );

  test('late handshake is discarded after workspace switch', () async {
    final received = Completer<void>();
    final release = Completer<void>();
    intercept = (request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/auth/token') {
        request.response.write(
          jsonEncode({
            'code': 0,
            'data': {'token': 'test-token'},
          }),
        );
      } else {
        received.complete();
        await release.future;
        request.response.write(jsonEncode({'code': 0, 'data': identity}));
      }
      await request.response.close();
    };
    final pending = expectLater(client.init(), throwsStateError);
    await received.future;
    localDataSource.selectWorkspace(directory.path, isPrimary: false);
    release.complete();
    await pending;
    expect(client.canUseWorkspace, isFalse);
  });

  test('disconnect invalidates a still-running handshake', () async {
    final received = Completer<void>();
    final release = Completer<void>();
    intercept = (request) async {
      if (request.uri.path == '/api/auth/token') {
        received.complete();
        await release.future;
        request.response.write(
          jsonEncode({
            'code': 0,
            'data': {'token': 'test-token'},
          }),
        );
      } else {
        request.response.write(jsonEncode({'code': 0, 'data': identity}));
      }
      await request.response.close();
    };
    final pending = expectLater(client.init(), throwsStateError);
    await received.future;
    client.disconnect();
    release.complete();
    await pending;
    expect(client.canUseWorkspace, isFalse);
  });

  test(
    'old engine or foreign protocol is refused even with a valid token',
    () async {
      identity['product'] = 'other';
      await expectLater(client.init(), throwsFormatException);
      identity['product'] = 'shufang';
      identity['protocol_version'] = 2;
      await expectLater(client.init(), throwsFormatException);
      expect(client.canUseWorkspace, isFalse);
    },
  );

  test('process mismatch clears binding without retrying a write', () async {
    await client.init();
    intercept = (request) async {
      operations.add(request.uri.path);
      request.response.statusCode = 409;
      request.response.headers.set('X-ShuFang-Binding-Invalid', '1');
      request.response.write(jsonEncode({'code': 409, 'message': 'changed'}));
      await request.response.close();
    };
    await expectLater(client.post('/api/write'), throwsStateError);
    expect(operations, ['/api/write']);
    expect(client.canUseWorkspace, isFalse);
  });

  test('auth redirects are rejected and never forwarded', () async {
    intercept = (request) async {
      operations.add(request.uri.path);
      request.response.statusCode = 302;
      request.response.headers.set('Location', '/api/trap');
      await request.response.close();
    };
    await expectLater(client.init(), throwsA(isA<HttpException>()));
    expect(operations, ['/api/auth/token']);
  });

  test('timed-out handshake cannot become a late connection', () async {
    final release = Completer<void>();
    final finished = Completer<void>();
    intercept = (request) async {
      await release.future;
      try {
        request.response.write(
          jsonEncode({
            'code': 0,
            'data': {'token': 'test-token'},
          }),
        );
        await request.response.close();
      } catch (_) {
        // The client closes its own handshake socket at the deadline.
      } finally {
        finished.complete();
      }
    };
    await expectLater(client.init(), throwsA(isA<TimeoutException>()));
    release.complete();
    await finished.future;
    expect(client.canUseWorkspace, isFalse);
  });

  test(
    'ordinary application conflict does not invalidate the engine',
    () async {
      await client.init();
      intercept = (request) async {
        request.response.statusCode = 409;
        request.response.write(
          jsonEncode({'code': 409, 'message': 'version conflict'}),
        );
        await request.response.close();
      };
      expect((await client.post('/api/edit')).code, 409);
      expect(client.canUseWorkspace, isTrue);
    },
  );

  test('malformed capability values are refused', () {
    (identity['capabilities'] as Map)['workspace_api'] = {'available': 'true'};
    expect(() => EngineCapabilities.fromJson(identity), throwsFormatException);
  });

  test('remote, credential-bearing and path-bearing endpoints are refused', () {
    for (final url in [
      'https://127.0.0.1:18766',
      'http://example.com',
      'http://user@localhost',
      'http://localhost/api',
      'http://localhost/?key=x',
      'http://localhost:0',
    ]) {
      expect(
        () => EngineEndpoint.resolve({'SHUFANG_ENGINE_URL': url}),
        throwsFormatException,
      );
    }
    expect(
      EngineEndpoint.resolve({'SHUFANG_ENGINE_URL': 'http://[::1]:18766'}).host,
      '::1',
    );
  });

  test(
    'portable launch finds source root and passes selected workspace',
    () async {
      final python = File(
        '${directory.path}/.venv/${Platform.isWindows ? 'Scripts/python.exe' : 'bin/python'}',
      );
      final app = File('${directory.path}/hermes_public/engine/app.py');
      await python.parent.create(recursive: true);
      await app.parent.create(recursive: true);
      await python.writeAsString('fixture');
      await app.writeAsString('fixture');
      final config =
          EngineLaunchConfig.resolve(
            environment: {},
            currentDirectory: app.parent.path,
            executable: app.path,
          )!;
      expect(config.app, app.path.replaceAll('/', Platform.pathSeparator));
      final env = config.launchEnvironment(
        directory.path,
        client.endpoint,
        inherited: {'HERMES_PRIVATE_ROOT': 'explicit-legacy-data'},
      );
      expect(env['HERMES_STORAGE_ROOT'], directory.absolute.path);
      expect(env['HERMES_ENGINE_PORT'], '${server.port}');
      expect(env['HERMES_PRIVATE_ROOT'], 'explicit-legacy-data');
      expect(env.containsKey('HERMES_ENV'), isFalse);
    },
  );

  test('explicit broken install does not fall back to another checkout', () {
    expect(
      () => EngineLaunchConfig.resolve(
        environment: {'SHUFANG_ENGINE_HOME': '${directory.path}/missing'},
        currentDirectory: Directory.current.path,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      () => EngineLaunchConfig.resolve(
        environment: {'SHUFANG_ENGINE_HOME': 'relative'},
      ),
      throwsFormatException,
    );
  });
}
