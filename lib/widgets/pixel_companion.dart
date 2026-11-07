// =============================================================================
// ShuFang Pixel Companion — CustomPainter Widget + State Controller
// =============================================================================
// 状态机驱动的像素小助手 Widget, 可嵌入 AI Chat Panel
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pixel_companion_palette.dart';

// 导出多角色相关类型, 方便外部只 import 本文件即可访问
export 'pixel_companion_palette.dart'
    show
        companionCharacters,
        CompanionCharacter,
        CompanionSprites,
        defaultCompanionCharacter;

/// 像素小助手 Widget
class PixelCompanion extends StatefulWidget {
  /// 显示尺寸 (边长, 默认 96)
  final double size;

  /// 兼容旧调用；实际绘制始终适配 [size]，避免放大时裁切。
  final int pixelSize;

  /// 边框圆角
  final double borderRadius;

  /// 背景色
  final Color? backgroundColor;

  /// 可选: 指定精灵集 (用于角色切换)
  final CompanionSprites? spritesOverride;
  final CompanionState state;
  final bool animate;

  const PixelCompanion({
    super.key,
    this.size = 96,
    this.pixelSize = 2,
    this.borderRadius = 8,
    this.backgroundColor,
    this.spritesOverride,
    this.state = CompanionState.idle,
    this.animate = true,
  });

  @override
  State<PixelCompanion> createState() => _PixelCompanionState();
}

class _PixelCompanionState extends State<PixelCompanion>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late CompanionSprites _sprites;
  int _frameIndex = 0;

  @override
  void initState() {
    super.initState();
    _sprites = widget.spritesOverride ?? defaultCompanionCharacter.builder();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPlayback();
  }

  @override
  void didUpdateWidget(covariant PixelCompanion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sprites = widget.spritesOverride ?? defaultCompanionCharacter.builder();
    final changed =
        oldWidget.state != widget.state ||
        oldWidget.spritesOverride != widget.spritesOverride;
    if (changed) {
      _frameIndex = 0;
    }
    _syncPlayback(restart: changed);
  }

  void _syncPlayback({bool restart = false}) {
    final count = _sprites.frameCount(widget.state);
    final animate =
        widget.animate &&
        count > 1 &&
        TickerMode.of(context) &&
        !MediaQuery.disableAnimationsOf(context);
    final frameMs = switch (widget.state) {
      CompanionState.idle => 900,
      CompanionState.thinking => 650,
      CompanionState.speaking || CompanionState.typing => 260,
      _ => 450,
    };
    final duration = Duration(milliseconds: frameMs * count);
    if (!animate) {
      _controller.stop();
      _frameIndex = 0;
    } else if (restart ||
        !_controller.isAnimating ||
        _controller.duration != duration) {
      _controller.duration = duration;
      _controller.value = 0;
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final next =
        (_controller.value * _sprites.frameCount(widget.state)).floor() %
        _sprites.frameCount(widget.state);
    if (next != _frameIndex) setState(() => _frameIndex = next);
  }

  @override
  Widget build(BuildContext context) {
    final frame = _sprites.getFrame(widget.state, _frameIndex);
    return RepaintBoundary(
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color:
              widget.backgroundColor ??
              Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(color: Theme.of(context).dividerColor, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            (widget.borderRadius - 1).clamp(0, double.infinity),
          ),
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _PixelPainter(frame: frame),
          ),
        ),
      ),
    );
  }
}

/// CustomPainter — 64×64 像素绘制
class _PixelPainter extends CustomPainter {
  final SpriteFrame frame;

  _PixelPainter({required this.frame});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    if (frame.image != null && frame.source != null) {
      final side = size.shortestSide;
      canvas.drawImageRect(
        frame.image!,
        frame.source!,
        Rect.fromLTWH(
          (size.width - side) / 2,
          (size.height - side) / 2,
          side,
          side,
        ),
        paint
          ..filterQuality = FilterQuality.none
          ..isAntiAlias = false,
      );
      return;
    }
    final pixels = frame.pixels;
    final pixelSize = size.shortestSide / 64;
    final gridSize = 64 * pixelSize;
    final offsetX = (size.width - gridSize) / 2;
    final offsetY = (size.height - gridSize) / 2;

    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        final idx = y * 64 + x;
        if (idx >= pixels.length) continue;
        final colorIdx = pixels[idx];
        if (colorIdx == 0) continue; // 透明
        if (colorIdx < 0 || colorIdx >= Pico8Palette.colors.length) continue;

        paint.color = Pico8Palette.colors[colorIdx];
        canvas.drawRect(
          Rect.fromLTWH(
            offsetX + x * pixelSize.toDouble(),
            offsetY + y * pixelSize.toDouble(),
            pixelSize.toDouble(),
            pixelSize.toDouble(),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelPainter old) {
    return old.frame != frame;
  }
}

/// 像素小助手 Controller — 全局状态管理
/// 由 companionControllerProvider 共享给设置、预览与 AI 面板。
class PixelCompanionController extends ChangeNotifier {
  Timer? _stateTimer;
  bool _disposed = false;
  int _preferenceRevision = 0;
  bool _visible = true;
  bool _animationsEnabled = true;
  bool _hintsEnabled = false;
  CompanionState _state = CompanionState.idle;
  List<int>? _customPixels;
  String _customName = '';
  String _characterId = defaultCompanionCharacter.id;
  CompanionSprites? _characterSprites;

  CompanionState get state => _state;
  List<int>? get customPixels => _customPixels;
  String get customName => _customName;
  bool get hasCustom => _customPixels != null;
  String get characterId => _characterId;
  CompanionSprites? get characterSprites => _characterSprites;
  bool get isDisposed => _disposed;
  int get preferenceRevision => _preferenceRevision;
  bool get visible => _visible;
  bool get animationsEnabled => _animationsEnabled;
  bool get hintsEnabled => _hintsEnabled;

  void setVisible(bool value) {
    if (_disposed || _visible == value) return;
    _visible = value;
    _preferenceRevision++;
    notifyListeners();
  }

  void setAnimationsEnabled(bool value) {
    if (_disposed || _animationsEnabled == value) return;
    _animationsEnabled = value;
    _preferenceRevision++;
    notifyListeners();
  }

  void setHintsEnabled(bool value) {
    if (_disposed || _hintsEnabled == value) return;
    _hintsEnabled = value;
    _preferenceRevision++;
    notifyListeners();
  }

  void setStateExt(CompanionState state) {
    if (_disposed) return;
    _stateTimer?.cancel();
    if (state == _state && state == CompanionState.idle) return;
    _state = state;
    notifyListeners();
    if (state == CompanionState.happy ||
        state == CompanionState.error ||
        state == CompanionState.hit ||
        state == CompanionState.eating) {
      _stateTimer = Timer(
        const Duration(seconds: 2),
        () => setStateExt(CompanionState.idle),
      );
    }
  }

  /// 兼容旧 API
  void setState(CompanionState state) => setStateExt(state);

  /// 设置用户上传的自定义精灵
  void setCustomSprite(List<int> pixels, String name) {
    if (_disposed) return;
    if (pixels.length != 4096 || pixels.any((p) => p < 0 || p > 15)) {
      throw ArgumentError('Sprite must be 4096 pixels (64x64)');
    }
    _customPixels = List<int>.unmodifiable(pixels);
    _customName = name;
    _preferenceRevision++;
    notifyListeners();
  }

  /// 清除自定义精灵, 恢复默认
  void clearCustomSprite() {
    if (_disposed) return;
    _customPixels = null;
    _customName = '';
    _preferenceRevision++;
    notifyListeners();
  }

  /// 切换角色
  void setCharacter(String charId) {
    if (_disposed) return;
    for (final ch in companionCharacters) {
      if (ch.id == charId) {
        _characterId = charId;
        _characterSprites = ch.builder();
        _customPixels = null;
        _customName = '';
        _preferenceRevision++;
        notifyListeners();
        return;
      }
    }
  }

  /// 获取当前角色信息
  CompanionCharacter? get currentCharacter {
    for (final ch in companionCharacters) {
      if (ch.id == _characterId) return ch;
    }
    return null;
  }

  /// 获取角色列表
  List<CompanionCharacter> get characters => companionCharacters;

  @override
  void dispose() {
    _disposed = true;
    _stateTimer?.cancel();
    super.dispose();
  }
}

/// 简化版 Widget — 使用全局 controller 驱动
class PixelCompanionLive extends StatelessWidget {
  final PixelCompanionController controller;
  final double size;
  final int pixelSize;
  final CompanionState? stateOverride;
  final bool? animate;

  const PixelCompanionLive({
    super.key,
    required this.controller,
    this.size = 96,
    this.pixelSize = 2,
    this.stateOverride,
    this.animate,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // 自定义精灵时, 用自定义像素
        if (controller.hasCustom) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: CustomPaint(
                size: Size(size, size),
                painter: _PixelPainter(
                  frame: SpriteFrame(controller.customPixels!),
                ),
              ),
            ),
          );
        }
        return PixelCompanion(
          size: size,
          pixelSize: pixelSize,
          spritesOverride:
              controller.characterSprites ??
              controller.currentCharacter?.builder(),
          state: stateOverride ?? controller.state,
          animate: animate ?? controller.animationsEnabled,
        );
      },
    );
  }
}

/// 用户上传图片 → 像素化处理
/// 在 Flutter 中通过 image_picker 或 file_picker 获取图片
class PixelateProcessor {
  /// 将图片数据 pixelate 到 64×64, 量化到 PICO-8 调色板
  /// 返回 `List<int>` pixels (4096 字节)
  static Future<List<int>> pixelate(Uint8List imageBytes) async {
    if (imageBytes.length > 2 * 1024 * 1024) {
      throw const FormatException('请选择不超过 2 MB 的图片');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(imageBytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? source;
    ui.Image? output;
    ui.Picture? picture;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final fittedSize =
          applyBoxFit(
            BoxFit.contain,
            Size(descriptor.width.toDouble(), descriptor.height.toDouble()),
            const Size(64, 64),
          ).destination;
      codec = await descriptor.instantiateCodec(
        targetWidth: fittedSize.width.round().clamp(1, 64),
        targetHeight: fittedSize.height.round().clamp(1, 64),
      );
      source = (await codec.getNextFrame()).image;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final fitted = applyBoxFit(
        BoxFit.contain,
        Size(source.width.toDouble(), source.height.toDouble()),
        const Size(64, 64),
      );
      canvas.drawImageRect(
        source,
        Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
        Alignment.center.inscribe(
          fitted.destination,
          const Rect.fromLTWH(0, 0, 64, 64),
        ),
        Paint()..filterQuality = FilterQuality.none,
      );
      picture = recorder.endRecording();
      output = await picture.toImage(64, 64);
      final byteData = await output.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) throw const FormatException('无法读取图片像素');
      final raw = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final pixels = <int>[];
      for (var i = 0; i < raw.length; i += 4) {
        final r = raw[i];
        final g = raw[i + 1];
        final b = raw[i + 2];
        final a = raw[i + 3];

        if (a < 128) {
          pixels.add(0); // 透明
        } else {
          pixels.add(_findNearestPico8(r, g, b));
        }
      }
      return pixels;
    } finally {
      output?.dispose();
      picture?.dispose();
      source?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  /// 在 PICO-8 调色板中找到与 RGB 最接近的颜色索引
  static int _findNearestPico8(int r, int g, int b) {
    var best = 1;
    var bestDist = 1 << 30;
    for (var i = 1; i < Pico8Palette.colors.length; i++) {
      final c = Pico8Palette.colors[i];
      final pr = (c.r * 255).round();
      final pg = (c.g * 255).round();
      final pb = (c.b * 255).round();
      final dist =
          (r - pr) * (r - pr) + (g - pg) * (g - pg) + (b - pb) * (b - pb);
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }
}

/// 用户自定义 Sprite 持久化 (使用 shared_preferences 或 path_provider)
/// 这里提供 JSON 序列化辅助函数
String encodeCustomSprite(List<int> pixels, String name) {
  return jsonEncode({'name': name, 'pixels': pixels, 'version': 1});
}

List<int>? decodeCustomSprite(String json) {
  try {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final pixels = data['pixels'] as List<dynamic>?;
    if (pixels == null || pixels.length != 4096) return null;
    if (pixels.any((e) => e is! int || e < 0 || e > 15)) return null;
    return pixels.cast<int>();
  } catch (e) {
    return null;
  }
}
