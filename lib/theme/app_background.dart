// 应用背景系统 — 提供条纹格/绿色护眼/自定义图等多种背景
// 编辑器/设定/灵感页统一复用, 通过 backgroundTypeProvider 切换

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 背景类型枚举
enum BackgroundType {
  /// 纯色 (跟随主题)
  plain,
  /// 条纹格 (横向细线, 类似笔记本)
  stripes,
  /// 绿色护眼 (淡绿底 + 细纹理)
  green,
  /// 自定义背景图
  custom,
}

/// 背景偏好持久化 (SharedPreferences)
/// 字段: type (枚举 name), customPath (自定义图路径)
class BackgroundPrefs {
  static const _kTypeKey = 'app_background_type';
  static const _kPathKey = 'app_background_path';

  static Future<BackgroundType> loadType() async {
    final sp = await SharedPreferences.getInstance();
    final name = sp.getString(_kTypeKey);
    return BackgroundType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => BackgroundType.stripes,
    );
  }

  static Future<String?> loadCustomPath() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kPathKey);
  }

  static Future<void> saveType(BackgroundType type) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kTypeKey, type.name);
  }

  static Future<void> saveCustomPath(String? path) async {
    final sp = await SharedPreferences.getInstance();
    if (path == null) {
      await sp.remove(_kPathKey);
    } else {
      await sp.setString(_kPathKey, path);
    }
  }
}

/// 背景类型 provider (持久化)
final backgroundTypeProvider =
    StateNotifierProvider<BackgroundTypeNotifier, BackgroundType>(
  (ref) => BackgroundTypeNotifier(),
);

/// 自定义背景图路径 provider (持久化)
final customBackgroundPathProvider =
    StateNotifierProvider<CustomPathNotifier, String?>(
  (ref) => CustomPathNotifier(),
);

class BackgroundTypeNotifier extends StateNotifier<BackgroundType> {
  BackgroundTypeNotifier() : super(BackgroundType.stripes);
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    state = await BackgroundPrefs.loadType();
    _loaded = true;
  }

  Future<void> set(BackgroundType type) async {
    state = type;
    await BackgroundPrefs.saveType(type);
  }
}

class CustomPathNotifier extends StateNotifier<String?> {
  CustomPathNotifier() : super(null);
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    state = await BackgroundPrefs.loadCustomPath();
    _loaded = true;
  }

  Future<void> set(String? path) async {
    state = path;
    await BackgroundPrefs.saveCustomPath(path);
  }
}

/// 应用背景 widget — 包裹任意子节点, 根据 provider 渲染背景层
/// 用法: AppBackground(child: ...)
class AppBackground extends ConsumerWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(backgroundTypeProvider);
    final customPath = ref.watch(customBackgroundPathProvider);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景层
        _buildBackground(context, type, customPath),
        // 内容层 (在背景上)
        child,
      ],
    );
  }

  Widget _buildBackground(
      BuildContext context, BackgroundType type, String? customPath) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (type) {
      case BackgroundType.plain:
        return const SizedBox.shrink();
      case BackgroundType.stripes:
        return CustomPaint(
          painter: _StripesPainter(dark: isDark),
          size: Size.infinite,
        );
      case BackgroundType.green:
        return CustomPaint(
          painter: _GreenPainter(dark: isDark),
          size: Size.infinite,
        );
      case BackgroundType.custom:
        if (customPath != null && File(customPath).existsSync()) {
          return Image.file(
            File(customPath),
            fit: BoxFit.cover,
            color: isDark
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.2),
            colorBlendMode: BlendMode.darken,
          );
        }
        // 自定义图未设置或文件丢失, 降级到条纹格
        return CustomPaint(
          painter: _StripesPainter(dark: isDark),
          size: Size.infinite,
        );
    }
  }
}

/// 条纹格背景画笔 — 横向细线 (笔记本风格)
/// 亮色: 浅灰线; 暗色: 深灰线
class _StripesPainter extends CustomPainter {
  final bool dark;
  _StripesPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    // 底色
    final bgColor = dark
        ? const Color(0xFF1A1A1A)
        : const Color(0xFFFAF8F2); // 米白底
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = bgColor,
    );

    // 横线 (每 32px 一条)
    final lineColor = dark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFD8D2C4); // 浅褐线
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.8;
    const step = 32.0;
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // 左边距红线 (笔记本装饰)
    final redPaint = Paint()
      ..color = (dark ? const Color(0xFF5A3030) : const Color(0xFFE8B4B4))
          .withValues(alpha: 0.6)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      const Offset(48, 0),
      Offset(48, size.height),
      redPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _StripesPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

/// 绿色护眼背景画笔 — 淡绿底 + 细横纹
class _GreenPainter extends CustomPainter {
  final bool dark;
  _GreenPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    // 淡绿底
    final bgColor = dark
        ? const Color(0xFF1B2A1F) // 暗绿
        : const Color(0xFFC8E6C9); // 护眼绿
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = bgColor,
    );

    // 细横纹 (更柔和)
    final lineColor = dark
        ? const Color(0xFF243528)
        : const Color(0xFFB2DFB4);
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5;
    const step = 28.0;
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GreenPainter oldDelegate) =>
      oldDelegate.dark != dark;
}
