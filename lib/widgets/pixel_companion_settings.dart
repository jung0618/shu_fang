/// 像素助手设置：本地形象、角色、动效和陪伴提示。
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../store/companion_store.dart';
import 'pixel_companion.dart';

Future<void> showCompanionSettingsSheet(
  BuildContext context,
  PixelCompanionController controller,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _CompanionSettingsDialog(controller: controller),
);

class _CompanionSettingsDialog extends StatefulWidget {
  final PixelCompanionController controller;
  const _CompanionSettingsDialog({required this.controller});

  @override
  State<_CompanionSettingsDialog> createState() =>
      _CompanionSettingsDialogState();
}

class _CompanionSettingsDialogState extends State<_CompanionSettingsDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _change(VoidCallback change) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      change();
      await saveCompanionPreferences(widget.controller);
    } catch (_) {
      if (mounted) setState(() => _error = '本次设置尚未保存，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndUpload() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      if (await picked.length() > 2 * 1024 * 1024) {
        throw const FormatException('请选择不超过 2 MB 的图片');
      }
      final pixels = await PixelateProcessor.pixelate(
        await picked.readAsBytes(),
      );
      if (!mounted) return;
      widget.controller.setCustomSprite(pixels, picked.name);
      await saveCompanionPreferences(widget.controller);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '图片未能保存，请选择 2 MB 以内的 PNG、JPG 或 GIF 后重试。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final controller = widget.controller;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome_outlined, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '写作伙伴',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed:
                              _busy ? null : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: PixelCompanionLive(
                        controller: controller,
                        size: 144,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      controller.hasCustom
                          ? '自定义 · ${controller.customName}'
                          : controller.currentCharacter?.name ?? '写作伙伴',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final character in companionCharacters)
                          ChoiceChip(
                            label: Text(character.name),
                            selected:
                                !controller.hasCustom &&
                                controller.characterId == character.id,
                            onSelected:
                                _busy
                                    ? null
                                    : (_) => _change(
                                      () =>
                                          controller.setCharacter(character.id),
                                    ),
                          ),
                      ],
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('显示写作伙伴'),
                      subtitle: const Text('在 AI 面板显示形象'),
                      value: controller.visible,
                      onChanged:
                          _busy
                              ? null
                              : (v) => _change(() => controller.setVisible(v)),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('播放角色动画'),
                      subtitle: const Text('也会遵循系统的减少动态效果设置'),
                      value: controller.animationsEnabled,
                      onChanged:
                          _busy
                              ? null
                              : (v) => _change(
                                () => controller.setAnimationsEnabled(v),
                              ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('保存与写作进度提示'),
                      subtitle: const Text('偶尔显示本地陪伴气泡，可随时关闭'),
                      value: controller.hintsEnabled,
                      onChanged:
                          _busy
                              ? null
                              : (v) =>
                                  _change(() => controller.setHintsEnabled(v)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _pickAndUpload,
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('选择本地图片'),
                        ),
                        if (controller.hasCustom)
                          TextButton(
                            onPressed:
                                _busy
                                    ? null
                                    : () =>
                                        _change(controller.clearCustomSprite),
                            child: const Text('恢复内置形象'),
                          ),
                        TextButton(
                          onPressed: _busy ? null : () => _change(() {}),
                          child: const Text('保存设置'),
                        ),
                      ],
                    ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_error!, style: TextStyle(color: cs.error)),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      '自定义图片取第一帧，保持比例缩放为 64×64 静态像素形象。角色、动画和提示均在本机运行，不额外调用 AI。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
