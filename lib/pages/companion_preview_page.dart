/// 像素小助手独立预览页
///
/// 用于:
///   - 查看当前角色已有动作、暂停动画及切换本地形象
///   - 不依赖 SSE 后端, 不依赖编辑器, 纯前端
///   - 状态/角色切换即时生效
///
/// 入口:
///   - 路由: AppRoute.companion
///   - 全局快捷键: Ctrl+Shift+P
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../store/companion_store.dart';
import '../store/navigation_store.dart';
import '../widgets/pixel_companion.dart';
import '../widgets/pixel_companion_palette.dart';
import '../widgets/pixel_companion_settings.dart';

class CompanionPreviewPage extends ConsumerStatefulWidget {
  const CompanionPreviewPage({super.key});

  @override
  ConsumerState<CompanionPreviewPage> createState() =>
      _CompanionPreviewPageState();
}

class _CompanionPreviewPageState extends ConsumerState<CompanionPreviewPage> {
  PixelCompanionController get _controller =>
      ref.read(companionControllerProvider);
  Timer? _loopTimer;
  double _scale = 3.0; // 预览放大倍率 (1 sprite = 64*3 = 192px)
  bool _autoLoop = false;

  List<CompanionState> get _availableStates {
    if (_controller.hasCustom) return const [CompanionState.idle];
    final sprites =
        _controller.characterSprites ?? _controller.currentCharacter?.builder();
    final states =
        CompanionState.values
            .where((state) => sprites?.frames[state]?.isNotEmpty ?? false)
            .toList();
    return states.isEmpty ? const [CompanionState.idle] : states;
  }

  void _startAutoLoop() {
    int i = 0;
    _autoLoop = true;
    _controller.setStateExt(_availableStates[0]);
    _loopTimer?.cancel();
    _loopTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (!mounted) return;
      final states = _availableStates;
      i = (i + 1) % states.length;
      _controller.setStateExt(states[i]);
    });
  }

  void _stopAutoLoop() {
    _autoLoop = false;
    _loopTimer?.cancel();
  }

  @override
  void dispose() {
    _autoLoop = false;
    _loopTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final spriteSize = (64 * _scale).clamp(64.0, 384.0);
    final allCharacters = companionCharacters;

    return Scaffold(
      appBar: AppBar(
        title: const Text('写作伙伴 · 动作预览'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _controller.setStateExt(CompanionState.idle);
            ref.read(navigationControllerProvider.notifier).back();
          },
        ),
        actions: [
          IconButton(
            tooltip: _autoLoop ? '停止自动循环' : '自动循环所有状态',
            icon: Icon(
              _autoLoop
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline,
            ),
            onPressed: () {
              setState(() {
                _autoLoop ? _stopAutoLoop() : _startAutoLoop();
              });
            },
          ),
          IconButton(
            tooltip: '设置 / 切换角色',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => showCompanionSettingsSheet(context, _controller),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final ch = _controller.currentCharacter;
          return SingleChildScrollView(
            child: Column(
              children: [
                // 主预览区
                SizedBox(
                  height: (MediaQuery.sizeOf(context).height * .48).clamp(
                    240.0,
                    460.0,
                  ),
                  child: Container(
                    width: double.infinity,
                    color:
                        b == Brightness.dark
                            ? const Color(0xFF1a1b1e)
                            : const Color(0xFFf7f7f9),
                    child: Stack(
                      children: [
                        // 棋盘格背景, 方便看透明度
                        Positioned.fill(
                          child: CustomPaint(painter: _CheckerPainter()),
                        ),
                        Center(
                          child: PixelCompanionLive(
                            controller: _controller,
                            size: spriteSize,
                            pixelSize: _scale.toInt(),
                          ),
                        ),
                        // 状态/角色/帧信息浮层
                        Positioned(
                          left: 16,
                          top: 16,
                          child: _InfoChip(
                            rows: [
                              ('角色', ch?.name ?? '未知'),
                              ('ID', ch?.id ?? '?'),
                              ('状态', _stateName(_controller.state)),
                              (
                                '尺寸',
                                '${spriteSize.toInt()}×${spriteSize.toInt()}',
                              ),
                              (
                                '帧',
                                _controller.hasCustom
                                    ? '自定义静态图'
                                    : '${(_controller.characterSprites ?? ch?.builder())?.frameCount(_controller.state) ?? 0} 帧',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 控制面板
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 状态选择
                      Text('动作', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            _availableStates.map((s) {
                              final selected = _controller.state == s;
                              return ChoiceChip(
                                label: Text(_stateName(s)),
                                selected: selected,
                                onSelected: (_) {
                                  setState(_stopAutoLoop);
                                  _controller.setStateExt(s);
                                },
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // 角色选择
                      Text('角色', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            allCharacters.map((c) {
                              final selected =
                                  _controller.currentCharacter?.id == c.id;
                              return ChoiceChip(
                                label: Text(c.name),
                                selected: selected,
                                onSelected: (_) async {
                                  _controller.setCharacter(c.id);
                                  try {
                                    await saveCompanionPreferences(_controller);
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('角色设置尚未保存，请在设置中重试'),
                                        ),
                                      );
                                    }
                                  }
                                },
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // 缩放滑块
                      Row(
                        children: [
                          const Text('缩放:'),
                          Expanded(
                            child: Slider(
                              value: _scale,
                              min: 1,
                              max: 6,
                              divisions: 10,
                              label: '${_scale.toStringAsFixed(1)}x',
                              onChanged: (v) => setState(() => _scale = v),
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              '${_scale.toStringAsFixed(1)}x',
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _stateName(CompanionState s) {
    switch (s) {
      case CompanionState.idle:
        return '待命';
      case CompanionState.typing:
        return '打字';
      case CompanionState.speaking:
        return '说话';
      case CompanionState.thinking:
        return '思考';
      case CompanionState.happy:
        return '开心';
      case CompanionState.error:
        return '错误';
      case CompanionState.hit:
        return '挨打';
      case CompanionState.eating:
        return '吃东西';
    }
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.rows});
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children:
            rows
                .map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        children: [
                          TextSpan(
                            text: '${r.$1}: ',
                            style: const TextStyle(color: Colors.white60),
                          ),
                          TextSpan(text: r.$2),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
      ),
    );
  }
}

/// 棋盘格背景 — 用于检查 sprite 透明区域
class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()..color = const Color(0xFF2a2c33);
    final p2 = Paint()..color = const Color(0xFF34363d);
    const cell = 16.0;
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final isAlt = ((x / cell).floor() + (y / cell).floor()) % 2 == 0;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), isAlt ? p1 : p2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter oldDelegate) => false;
}
