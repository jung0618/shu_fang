/// 写作伙伴偏好只保存在本机，不进入写作上下文或训练记录。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/pixel_companion.dart';

const _preferencesKey = 'pixel_companion_preferences_v2';

final companionControllerProvider =
    ChangeNotifierProvider<PixelCompanionController>((ref) {
      final controller = PixelCompanionController();
      restoreCompanionPreferences(controller);
      return controller;
    });

Future<void> restoreCompanionPreferences(
  PixelCompanionController controller,
) async {
  final revision = controller.preferenceRevision;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (controller.isDisposed || controller.preferenceRevision != revision) {
      return;
    }
    final encoded = prefs.getString(_preferencesKey);
    if (encoded != null) {
      final data = jsonDecode(encoded);
      if (data is! Map<String, dynamic> || data['version'] != 2) return;
      final character = data['character'];
      if (character is String) controller.setCharacter(character);
      if (data['visible'] is bool) {
        controller.setVisible(data['visible'] as bool);
      }
      if (data['animations'] is bool) {
        controller.setAnimationsEnabled(data['animations'] as bool);
      }
      if (data['hints'] is bool) {
        controller.setHintsEnabled(data['hints'] as bool);
      }
      final custom = decodeCustomSprite(encoded);
      if (custom != null) {
        controller.setCustomSprite(
          custom,
          data['name'] is String ? data['name'] as String : '自定义形象',
        );
      }
      return;
    }
    // 兼容旧版；损坏的单个像素不会阻塞设置或应用启动。
    final character = prefs.getString('pixel_companion_character');
    if (character != null) controller.setCharacter(character);
    final raw = prefs.getStringList('pixel_companion_custom_pixels');
    if (raw == null || raw.length != 4096) return;
    final pixels = raw.map(int.tryParse).toList();
    if (pixels.any((p) => p == null || p < 0 || p > 15)) return;
    controller.setCustomSprite(
      pixels.cast<int>(),
      prefs.getString('pixel_companion_custom_name') ?? '自定义形象',
    );
  } catch (_) {
    // 偏好损坏时保留当前角色，不影响正文和存储。
  }
}

Future<void>? _saveTail;

/// 一份 JSON 原子替换整个偏好快照；串行写避免快切设置被旧写入覆盖。
Future<void> saveCompanionPreferences(PixelCompanionController controller) {
  final encoded = jsonEncode({
    'version': 2,
    'character': controller.characterId,
    'visible': controller.visible,
    'animations': controller.animationsEnabled,
    'hints': controller.hintsEnabled,
    'pixels': controller.customPixels,
    'name': controller.customName,
  });
  Future<void> writeSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_preferencesKey, encoded)) {
      throw StateError('写作伙伴设置未能保存');
    }
  }

  final previous = _saveTail;
  final write =
      previous == null
          ? writeSnapshot()
          : previous.then<void>(
            (_) => writeSnapshot(),
            onError: (Object _, StackTrace __) => writeSnapshot(),
          );
  _saveTail = write;
  return write.whenComplete(() {
    if (identical(_saveTail, write)) _saveTail = null;
  });
}
