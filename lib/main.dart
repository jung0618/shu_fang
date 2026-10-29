import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'config/flavor.dart';
import 'store/local_prefs.dart';
import 'theme/colors.dart';
import 'widgets/pixel_companion_palette.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);

  // 加载全局偏好 (跨会话 UI 状态) — 必须在 ProviderScope 创建前完成
  await PrefsController.init();

  // T-25: 预加载像素精灵数据 (从 assets/companion/*.json 加载到内存缓存)
  await CompanionSpriteLoader.preload();

  // D21 修复: 加 center: true, 启动时强制居中, 防止还原持久化的 (-18286,-18286) bug
  // T-12: 窗口背景色改用设计系统 AppColors.darkBg (替换硬编码 Color(0xFF1A1B1E))
  const windowOptions = WindowOptions(
    size: Size(1400, 900),
    minimumSize: Size(1024, 680),
    center: true,
    title: kShuFangWindowTitle,
    backgroundColor: AppColors.darkBg,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: ShuFangApp(manageWindow: true)));
}
