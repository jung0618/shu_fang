import 'dart:io';

class StoragePaths {
  static bool validName(String value) {
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.endsWith('.') ||
        value.endsWith(' ')) {
      return false;
    }
    if (RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(value)) return false;
    final stem = value.split('.').first.toUpperCase();
    return !RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem);
  }

  static String resolveBaseRoot() {
    final override = Platform.environment['HERMES_STORAGE_ROOT']?.trim();
    if (override != null && override.isNotEmpty) {
      return Directory(override).absolute.path;
    }
    // Preserve this developer workspace's existing manuscripts without moving
    // them. New installations do not require the developer's D: drive.
    const legacy = r'D:\Hermes\shufang_storage';
    if (Platform.isWindows && Directory(legacy).existsSync()) return legacy;
    final home =
        Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    final appData = Platform.isWindows ? Platform.environment['APPDATA'] : null;
    final base = appData ?? home;
    if (base == null || base.isEmpty) {
      throw const FileSystemException('无法确定写作数据目录，请设置 HERMES_STORAGE_ROOT');
    }
    return '$base${Platform.pathSeparator}ShuFang${Platform.pathSeparator}storage';
  }
}
