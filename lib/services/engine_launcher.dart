/// Local engine startup and authenticated workspace connection.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../store/local_data_source.dart';
import 'engine_config.dart';

enum EngineStatus { unknown, starting, ready, failed }

enum EngineStartPhase { spawning, waiting, ready, failed }

class EngineStartProgress {
  final EngineStartPhase phase;
  final String message;
  final String? expectation;
  const EngineStartProgress({
    required this.phase,
    required this.message,
    this.expectation,
  });
  bool get isTerminal =>
      phase == EngineStartPhase.ready || phase == EngineStartPhase.failed;
}

final engineStatusProvider = StateProvider<EngineStatus>(
  (_) => EngineStatus.unknown,
);
final engineMessageProvider = StateProvider<String?>((_) => null);
final engineBindingProvider = StreamProvider((ref) async* {
  yield apiClient.capabilities;
  yield* apiClient.bindingChanges;
});

class EngineLauncher {
  EngineLauncher._();
  static int _operation = 0;

  static bool _active(
    StateController<EngineStatus> status,
    int operation,
    int revision,
  ) =>
      status.mounted &&
      operation == _operation &&
      revision == localDataSource.sessionRevision;

  static void reset() {
    _operation++;
    apiClient.disconnect();
  }

  static Future<void> probeEngine(WidgetRef ref) async {
    if (!localDataSource.hasWorkspace ||
        !ref.context.mounted ||
        ref.read(engineStatusProvider) == EngineStatus.starting) {
      return;
    }
    final status = ref.read(engineStatusProvider.notifier);
    final messageState = ref.read(engineMessageProvider.notifier);
    final operation = ++_operation;
    final revision = localDataSource.sessionRevision;
    status.state = EngineStatus.starting;
    messageState.state = '正在核对引擎与工作区…';
    try {
      await apiClient.init();
      if (!_active(status, operation, revision)) return;
      status.state = EngineStatus.ready;
      messageState.state = '已连接当前工作区；模型与训练状态另行核对。';
    } catch (error) {
      if (!_active(status, operation, revision)) return;
      status.state = EngineStatus.failed;
      messageState.state = '$error';
    }
  }

  static Future<bool> startEngine(
    WidgetRef ref, {
    void Function(EngineStartProgress)? onProgress,
  }) async {
    if (!localDataSource.hasWorkspace ||
        !ref.context.mounted ||
        ref.read(engineStatusProvider) == EngineStatus.starting) {
      return false;
    }
    final status = ref.read(engineStatusProvider.notifier);
    final messageState = ref.read(engineMessageProvider.notifier);
    final operation = ++_operation;
    final revision = localDataSource.sessionRevision;
    final root = localDataSource.storageRoot;
    status.state = EngineStatus.starting;
    void progress(EngineStartPhase phase, String message) {
      if (!_active(status, operation, revision)) return;
      messageState.state = message;
      onProgress?.call(EngineStartProgress(phase: phase, message: message));
    }

    try {
      // Always reauthenticate, even if a previous probe was successful.
      try {
        await apiClient.init();
        if (!_active(status, operation, revision)) return false;
        status.state = EngineStatus.ready;
        progress(EngineStartPhase.ready, '已连接当前工作区。');
        return true;
      } catch (_) {
        if (!_active(status, operation, revision)) return false;
      }
      if (await _portInUse()) {
        throw StateError('此地址已有服务，但无法连接当前工作区。请核对引擎版本、目录和地址；不会结束已有进程。');
      }
      if (!_active(status, operation, revision)) return false;
      final config = EngineLaunchConfig.resolve();
      if (config == null) throw StateError('未找到配套引擎。请配置安装位置，或连接已启动的本机引擎。');
      progress(EngineStartPhase.spawning, '正在为当前工作区启动引擎…');
      await _spawn(config, root, () => _active(status, operation, revision));
      for (var attempt = 0; attempt < 10; attempt++) {
        if (!_active(status, operation, revision)) return false;
        progress(EngineStartPhase.waiting, '等待引擎并核对工作区…（${attempt + 1}/10）');
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!_active(status, operation, revision)) return false;
        try {
          await apiClient.init();
          if (!_active(status, operation, revision)) return false;
          status.state = EngineStatus.ready;
          progress(EngineStartPhase.ready, '已连接当前工作区。');
          return true;
        } catch (_) {
          if (attempt == 9) rethrow;
        }
      }
    } catch (error) {
      if (!_active(status, operation, revision)) return false;
      status.state = EngineStatus.failed;
      progress(EngineStartPhase.failed, '$error');
    }
    return false;
  }

  static Future<void> _spawn(
    EngineLaunchConfig config,
    String root,
    bool Function() active,
  ) async {
    final endpoint = apiClient.endpoint;
    final logFile = File(
      '$root${Platform.pathSeparator}.shufang${Platform.pathSeparator}logs${Platform.pathSeparator}engine.log',
    );
    await logFile.parent.create(recursive: true);
    // Open before spawning, so a log permission error cannot hide a live child.
    final log = await logFile.open(mode: FileMode.append);
    try {
      if (!active()) throw StateError('工作区已切换，启动已取消。');
      final process = await Process.start(
        config.python,
        [
          config.app,
          '--port',
          '${endpoint.port}',
          '--host',
          endpoint.host == 'localhost' ? '127.0.0.1' : endpoint.host,
          '--no-gui',
        ],
        workingDirectory: config.home,
        environment: config.launchEnvironment(root, endpoint),
        mode: ProcessStartMode.detachedWithStdio,
      );
      await process.stdin.close().catchError((Object _) {});
      // Both streams must finish before closing their shared log handle.
      Future<void> pending = Future<void>.value();
      void append(List<int> bytes) {
        pending = pending
            .then((_) async {
              await log.writeFrom(bytes);
            })
            .catchError((Object _) {});
      }

      unawaited(
        Future.wait([
              process.stdout.forEach(append).catchError((Object _) {}),
              process.stderr.forEach(append).catchError((Object _) {}),
            ])
            .then((_) async {
              await pending;
              await log.close();
            })
            .catchError((Object _) {}),
      );
    } catch (_) {
      await log.close();
      rethrow;
    }
  }

  static Future<bool> _portInUse() async {
    try {
      final socket = await Socket.connect(
        apiClient.endpoint.host,
        apiClient.endpoint.port,
        timeout: const Duration(milliseconds: 500),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
