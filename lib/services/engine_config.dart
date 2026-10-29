import 'dart:io';

/// Local engine transport. Never send the locally acquired token off-device.
class EngineEndpoint {
  static Uri resolve([Map<String, String>? environment]) {
    final raw = (environment ?? Platform.environment)['SHUFANG_ENGINE_URL'];
    final uri = Uri.parse(raw ?? 'http://127.0.0.1:18766');
    if (uri.scheme != 'http' ||
        !const {'127.0.0.1', '::1', 'localhost'}.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException('引擎地址须为本机 HTTP 地址，且不含路径或账号。');
    }
    return uri.replace(path: '');
  }
}

/// Source checkout or an explicitly configured installation, without machine paths.
class EngineLaunchConfig {
  final String python;
  final String app;
  final String home;
  const EngineLaunchConfig(this.python, this.app, this.home);

  static EngineLaunchConfig? resolve({
    Map<String, String>? environment,
    String? currentDirectory,
    String? executable,
  }) {
    final env = environment ?? Platform.environment;
    final explicitHome = env['SHUFANG_ENGINE_HOME'];
    final explicitPython = env['SHUFANG_ENGINE_PYTHON'];
    final explicitApp = env['SHUFANG_ENGINE_APP'];
    final candidates = <String>[];
    if (explicitHome != null) {
      candidates.add(explicitHome);
    } else if (explicitApp != null && explicitPython != null) {
      candidates.add(File(explicitApp).absolute.parent.path);
    } else {
      for (final start in [
        currentDirectory ?? Directory.current.path,
        File(executable ?? Platform.resolvedExecutable).parent.path,
      ]) {
        var directory = Directory(start).absolute;
        for (var i = 0; i < 10; i++) {
          candidates.add(directory.path);
          if (directory.parent.path == directory.path) break;
          directory = directory.parent;
        }
      }
    }
    for (final candidate in candidates) {
      if (!Directory(candidate).isAbsolute ||
          (explicitPython != null && !File(explicitPython).isAbsolute) ||
          (explicitApp != null && !File(explicitApp).isAbsolute)) {
        throw const FormatException('引擎安装配置须使用绝对路径。');
      }
      final sep = Platform.pathSeparator;
      final python =
          explicitPython ??
          '$candidate$sep.venv$sep${Platform.isWindows ? 'Scripts${sep}python.exe' : 'bin${sep}python'}';
      final app =
          explicitApp ??
          '$candidate${sep}hermes_public${sep}engine${sep}app.py';
      if (File(python).existsSync() && File(app).existsSync()) {
        return EngineLaunchConfig(python, app, candidate);
      }
    }
    // Explicit configuration must not silently fall back to a different install.
    if (explicitHome != null || explicitPython != null || explicitApp != null) {
      throw const FileSystemException('配置的引擎或项目虚拟环境不存在。');
    }
    return null;
  }

  Map<String, String> launchEnvironment(
    String workspaceRoot,
    Uri endpoint, {
    Map<String, String>? inherited,
  }) {
    return {
      ...(inherited ?? Platform.environment),
      'HERMES_STORAGE_ROOT': Directory(workspaceRoot).absolute.path,
      'HERMES_ENGINE_PORT': '${endpoint.port}',
      'HERMES_ENGINE_HOST':
          endpoint.host == 'localhost' ? '127.0.0.1' : endpoint.host,
      'PYTHONUNBUFFERED': '1',
    };
  }
}
