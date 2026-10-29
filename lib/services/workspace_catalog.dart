import 'dart:io';

import 'storage_paths.dart';

/// A directory on this device, not an account or an access control boundary.
class LocalWorkspace {
  final String id;
  final String name;
  final String path;
  final bool isPrimary;

  const LocalWorkspace({
    required this.id,
    required this.name,
    required this.path,
    this.isPrimary = false,
  });
}

class WorkspaceCatalog {
  static const primaryId = '@primary';

  static Future<List<LocalWorkspace>> discover() async {
    final base = StoragePaths.resolveBaseRoot();
    final result = <LocalWorkspace>[
      LocalWorkspace(id: primaryId, name: '主工作区', path: base, isPrimary: true),
    ];
    final users = Directory('$base${Platform.pathSeparator}users');
    if (await users.exists()) {
      await for (final entry in users.list(followLinks: false)) {
        if (entry is! Directory) continue;
        final name = entry.path.split(RegExp(r'[/\\]')).last;
        if (!StoragePaths.validName(name)) continue;
        result.add(
          LocalWorkspace(id: 'users/$name', name: name, path: entry.path),
        );
      }
    }
    result.sort((a, b) {
      if (a.id == b.id) return 0;
      if (a.isPrimary) return -1;
      if (b.isPrimary) return 1;
      return a.name.compareTo(b.name);
    });
    return result;
  }

  static Future<LocalWorkspace> create(String input) async {
    final name = input.trim();
    if (!StoragePaths.validName(name) || name.length > 64) {
      throw const FormatException('请输入 1–64 个字符的名称，避开路径符号和系统保留名称。');
    }
    final base = StoragePaths.resolveBaseRoot();
    final path =
        '$base${Platform.pathSeparator}users${Platform.pathSeparator}$name';
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FormatException('这个名称已存在，请在列表中打开，或换一个名称。');
    }
    await Directory(
      '$path${Platform.pathSeparator}books',
    ).create(recursive: true);
    return LocalWorkspace(id: 'users/$name', name: name, path: path);
  }
}
