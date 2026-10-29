// =============================================================================
// ShuFang Pixel Companion — Sprite Palette & Data Loader
// =============================================================================
// T-25: PICO-8 帧数据已外置到 assets/companion/*.json
//   - yanyu.json     颜如玉 (8 状态 × 2 帧)
//   - huangjinwu.json 黄金屋 (8 状态 × 2 帧)
// 启动时由 CompanionSpriteLoader.preload() 一次性加载到内存缓存,
// 运行期通过 CompanionSpriteLoader.get(charId) 同步访问, 保持原有同步 API 不变.
// -----------------------------------------------------------------------------
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Companion 状态机 (8 状态)
enum CompanionState {
  idle,
  typing,
  speaking,
  thinking,
  happy,
  error,
  hit,
  eating,
}

/// PICO-8 16 色调色板 (Color list)
class Pico8Palette {
  static const List<Color> colors = [
    Color.fromARGB(255, 0, 0, 0),
    Color.fromARGB(255, 29, 43, 83),
    Color.fromARGB(255, 126, 37, 83),
    Color.fromARGB(255, 0, 135, 81),
    Color.fromARGB(255, 171, 82, 54),
    Color.fromARGB(255, 95, 87, 79),
    Color.fromARGB(255, 194, 195, 199),
    Color.fromARGB(255, 255, 241, 232),
    Color.fromARGB(255, 255, 0, 77),
    Color.fromARGB(255, 255, 163, 0),
    Color.fromARGB(255, 255, 236, 39),
    Color.fromARGB(255, 0, 228, 54),
    Color.fromARGB(255, 41, 173, 255),
    Color.fromARGB(255, 131, 118, 156),
    Color.fromARGB(255, 255, 119, 168),
    Color.fromARGB(255, 255, 204, 163),
  ];

  /// 状态色 (用于 HUD 标签)
  static Color colorFor(CompanionState state, double b) {
    switch (state) {
      case CompanionState.idle:
        return Color.lerp(colors[6], colors[12], b) ?? colors[6];
      case CompanionState.typing:
        return Color.lerp(colors[6], colors[9], b) ?? colors[6];
      case CompanionState.speaking:
        return Color.lerp(colors[6], colors[8], b) ?? colors[6];
      case CompanionState.thinking:
        return Color.lerp(colors[6], colors[10], b) ?? colors[6];
      case CompanionState.happy:
        return Color.lerp(colors[6], colors[11], b) ?? colors[6];
      case CompanionState.error:
        return Color.lerp(colors[6], colors[14], b) ?? colors[6];
      case CompanionState.hit:
        return Color.lerp(colors[6], colors[2], b) ?? colors[6];
      case CompanionState.eating:
        return Color.lerp(colors[6], colors[4], b) ?? colors[6];
    }
  }
}

/// 单帧精灵 (64x64 = 4096 PICO-8 索引)
class SpriteFrame {
  final List<int> pixels;
  final ui.Image? image;
  final Rect? source;
  const SpriteFrame(this.pixels) : image = null, source = null;
  const SpriteFrame.atlas(this.image, this.source) : pixels = const [];
}

/// PICO-8 数据 → `List<int>` 解析器 (顶层函数)
List<int> parseSpriteData(String data) {
  final pixels =
      data
          .replaceAll(r'\r\n', '\n')
          .replaceAll(r'\n', '\n')
          .split(RegExp(r'[\s,]+'))
          .where((s) => s.trim().isNotEmpty)
          .map(int.parse)
          .toList();
  if (pixels.length != 4096 || pixels.any((p) => p < 0 || p > 15)) {
    throw const FormatException('精灵帧必须包含 4096 个 0–15 的颜色索引');
  }
  return List.unmodifiable(pixels);
}

/// 多状态精灵集 (8 状态 × 2 帧)
class CompanionSprites {
  final Map<CompanionState, List<SpriteFrame>> frames;
  const CompanionSprites({required this.frames});

  bool get isEmpty => frames.values.every((list) => list.isEmpty);

  /// 某状态有多少帧
  int frameCount(CompanionState s) {
    final list = frames[s];
    if (list == null || list.isEmpty) {
      final idleCount = frames[CompanionState.idle]?.length ?? 0;
      return idleCount > 0 ? idleCount : 1;
    }
    return list.length;
  }

  /// 某状态的第 i 帧 (越界回退 idle)
  SpriteFrame getFrame(CompanionState s, int i) {
    final list = frames[s];
    if (list == null || list.isEmpty) {
      final idle = frames[CompanionState.idle];
      return idle != null && idle.isNotEmpty
          ? idle[i % idle.length]
          : const SpriteFrame([]);
    }
    return list[i % list.length];
  }

  List<SpriteFrame> framesOf(CompanionState s) => frames[s] ?? const [];
}

// =============================================================================
//  T-25: 数据外置 + 异步预加载 + 同步缓存
// =============================================================================

/// 精灵数据加载器: 启动时预加载 JSON, 运行期同步访问.
class CompanionSpriteLoader {
  CompanionSpriteLoader._();

  static final Map<String, CompanionSprites> _cache = {};
  static final Map<String, String> loadErrors = {};

  /// 预加载所有角色精灵数据 (main.dart 启动时调用一次)
  static Future<void> preload() async {
    for (final charId in const ['yanyu', 'huangjinwu']) {
      if (_cache.containsKey(charId)) continue;
      try {
        final jsonStr = await rootBundle.loadString(
          'assets/companion/$charId.json',
        );
        _cache[charId] = _parseJson(jsonStr);
      } catch (e) {
        // 加载失败不阻塞启动, 运行期 get() 会返回空集
        debugPrint('CompanionSpriteLoader: failed to load $charId: $e');
        loadErrors[charId] = '$e';
      }
    }
    // 新的透明图集使用实际绘制的关键帧；尚未提供的动作回退到待命。
    // 旧 JSON 保留供历史素材兼容，默认角色优先使用干净图集。
    try {
      if (_atlasLoaded) return;
      final bytes = await rootBundle.load(
        'assets/companion/huangjinwu-core-v3.png',
      );
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      try {
        final image = (await codec.getNextFrame()).image;
        // Generated art is not an exact registered grid. These reviewed windows
        // preserve full boots/tails and use one scale and foot baseline per row.
        // Keep this metadata together with the versioned asset.
        if (image.width != 1774 || image.height != 887) {
          image.dispose();
          throw const FormatException('核心图集尺寸与裁切元数据不匹配');
        }
        const sources = [
          Rect.fromLTWH(75.5, 35, 420, 420),
          Rect.fromLTWH(482.5, 35, 420, 420),
          Rect.fromLTWH(904.5, 35, 420, 420),
          Rect.fromLTWH(1316.5, 35, 420, 420),
          Rect.fromLTWH(66, 450, 420, 420),
          Rect.fromLTWH(473.5, 450, 420, 420),
          Rect.fromLTWH(902.5, 450, 420, 420),
          Rect.fromLTWH(1310, 450, 420, 420),
        ];
        final states = [
          CompanionState.idle,
          CompanionState.thinking,
          CompanionState.speaking,
          CompanionState.happy,
        ];
        final frames = <CompanionState, List<SpriteFrame>>{};
        for (var s = 0; s < states.length; s++) {
          frames[states[s]] = List.unmodifiable([
            for (var i = 0; i < 2; i++)
              SpriteFrame.atlas(image, sources[s * 2 + i]),
          ]);
        }
        _cache['huangjinwu'] = CompanionSprites(
          frames: Map.unmodifiable(frames),
        );
        _atlasLoaded = true;
      } finally {
        codec.dispose();
      }
    } catch (e) {
      loadErrors['huangjinwu-core-v3'] = '$e';
      debugPrint('CompanionSpriteLoader: core atlas unavailable: $e');
    }
  }

  static bool _atlasLoaded = false;

  /// 同步获取已缓存的精灵 (未加载完成时返回空集)
  static CompanionSprites get(String charId) {
    return _cache[charId] ?? const CompanionSprites(frames: {});
  }

  /// 解析 JSON → CompanionSprites
  static CompanionSprites _parseJson(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final frames = <CompanionState, List<SpriteFrame>>{};
    for (final entry in data.entries) {
      final matching = CompanionState.values.where((s) => s.name == entry.key);
      if (matching.isEmpty) continue;
      final state = matching.first;
      final frameStrs = entry.value as List<dynamic>;
      frames[state] = List.unmodifiable(
        frameStrs
            .map((s) => SpriteFrame(parseSpriteData(s as String)))
            .toList(),
      );
    }
    if (frames[CompanionState.idle]?.isNotEmpty != true) {
      throw const FormatException('精灵缺少待命帧');
    }
    return CompanionSprites(frames: Map.unmodifiable(frames));
  }
}

// =============================================================================
//  角色注册表
// =============================================================================

class CompanionCharacter {
  final String id;
  final String name;
  final String description;
  final CompanionSprites Function() builder;

  const CompanionCharacter({
    required this.id,
    required this.name,
    required this.description,
    required this.builder,
  });
}

const List<CompanionCharacter> companionCharacters = [
  CompanionCharacter(
    id: 'huangjinwu',
    name: '黄金屋',
    description: '蓝外套红围巾狼耳娘, 活泼系',
    builder: _buildHuangjinwu,
  ),
  CompanionCharacter(
    id: 'yanyu',
    name: '颜如玉',
    description: '白围裙猫耳娘, 温柔系',
    builder: _buildYanyu,
  ),
];

/// 默认角色 (黄金屋)
const CompanionCharacter defaultCompanionCharacter = CompanionCharacter(
  id: 'huangjinwu',
  name: '黄金屋',
  description: '蓝外套红围巾狼耳娘, 活泼系',
  builder: _buildHuangjinwu,
);

// T-25: builder 从内存缓存同步获取 (预加载在 main.dart 完成)
CompanionSprites _buildYanyu() => CompanionSpriteLoader.get('yanyu');
CompanionSprites _buildHuangjinwu() => CompanionSpriteLoader.get('huangjinwu');

/// 兼容旧 API (错别字版本: buildYanruyuSprites → buildYanyuSprites)
/// pixel_companion.dart:63 历史拼写
CompanionSprites buildYanruyuSprites() => _buildYanyu();
