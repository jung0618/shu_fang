import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shufang_flutter/pages/companion_preview_page.dart';
import 'package:shufang_flutter/store/companion_store.dart';
import 'package:shufang_flutter/widgets/companion_bubble.dart';
import 'package:shufang_flutter/widgets/pixel_companion.dart';
import 'package:shufang_flutter/widgets/pixel_companion_palette.dart';
import 'package:shufang_flutter/widgets/pixel_companion_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(CompanionSpriteLoader.preload);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('bundled assets load and four clean core loops are drawable', () async {
    expect(CompanionSpriteLoader.loadErrors, isEmpty);
    for (final character in companionCharacters) {
      expect(character.builder().isEmpty, isFalse);
    }
    final sprites = defaultCompanionCharacter.builder();
    for (final state in [
      CompanionState.idle,
      CompanionState.thinking,
      CompanionState.speaking,
      CompanionState.happy,
    ]) {
      expect(sprites.frameCount(state), 2);
      final frame = sprites.getFrame(state, 0);
      expect(frame.image, isNotNull);
      expect(frame.source!.width, greaterThan(0));
    }
    final image = sprites.getFrame(CompanionState.idle, 0).image!;
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    expect(
      bytes.getUint8(3),
      0,
      reason: 'atlas background must be transparent',
    );
    expect(bytes.buffer.asUint8List().any((value) => value != 0), isTrue);
    // A transparent corner alone cannot detect artwork cut by an atlas seam.
    // Keep visible pixels away from all four cell edges, including feet/tails.
    for (final frames in sprites.frames.values) {
      for (final frame in frames) {
        final cell = frame.source!;
        final margin = cell.shortestSide * .025;
        var visiblePixels = 0;
        for (var y = cell.top.ceil(); y < cell.bottom.floor(); y++) {
          for (var x = cell.left.ceil(); x < cell.right.floor(); x++) {
            if (bytes.getUint8((y * image.width + x) * 4 + 3) < 128) {
              continue;
            }
            visiblePixels++;
            if (x < cell.left + margin ||
                x >= cell.right - margin ||
                y < cell.top + margin ||
                y >= cell.bottom - margin) {
              fail('Visible artwork touches sprite cell edge: $cell ($x, $y)');
            }
          }
        }
        expect(visiblePixels, greaterThan(0));
      }
    }
  });

  test(
    'legacy literal newlines parse, malformed frames fail and missing states are safe',
    () {
      final row = List.filled(64, '7').join(',');
      expect(parseSpriteData(List.filled(64, row).join(r'\n')).length, 4096);
      expect(() => parseSpriteData('1,2,3'), throwsFormatException);
      expect(
        () => parseSpriteData(List.filled(4096, '16').join(',')),
        throwsFormatException,
      );
      const empty = CompanionSprites(frames: {});
      expect(empty.getFrame(CompanionState.thinking, 17).pixels, isEmpty);
      expect(empty.frameCount(CompanionState.idle), greaterThan(0));
    },
  );

  test(
    'one saved snapshot restores role, switches and immutable custom image',
    () async {
      final source = PixelCompanionController();
      final restored = PixelCompanionController();
      addTearDown(source.dispose);
      addTearDown(restored.dispose);
      source.setCharacter('yanyu');
      source.setAnimationsEnabled(false);
      source.setHintsEnabled(true);
      source.setVisible(false);
      final pixels = List.filled(4096, 7);
      source.setCustomSprite(pixels, '本地图片.png');
      pixels[0] = 3;
      await saveCompanionPreferences(source);
      await restoreCompanionPreferences(restored);
      expect(restored.characterId, 'yanyu');
      expect(restored.animationsEnabled, isFalse);
      expect(restored.hintsEnabled, isTrue);
      expect(restored.visible, isFalse);
      expect(restored.customPixels!.first, 7);
      expect(restored.customName, '本地图片.png');
      expect(() => restored.customPixels![0] = 2, throwsUnsupportedError);
    },
  );

  test(
    'corrupt legacy pixels cannot prevent restoring a usable built-in role',
    () async {
      SharedPreferences.setMockInitialValues({
        'pixel_companion_character': 'yanyu',
        'pixel_companion_custom_pixels': List.filled(4096, 'not-an-int'),
      });
      final controller = PixelCompanionController();
      addTearDown(controller.dispose);
      await restoreCompanionPreferences(controller);
      expect(controller.characterId, 'yanyu');
      expect(controller.hasCustom, isFalse);
    },
  );

  test(
    'late restore cannot overwrite a user action; rapid saves retain the latest choice',
    () async {
      SharedPreferences.setMockInitialValues({
        'pixel_companion_preferences_v2': jsonEncode({
          'version': 2,
          'visible': true,
        }),
      });
      final controller = PixelCompanionController();
      final restored = PixelCompanionController();
      addTearDown(controller.dispose);
      addTearDown(restored.dispose);
      final loading = restoreCompanionPreferences(controller);
      controller.setVisible(false);
      await loading;
      expect(controller.visible, isFalse);
      final first = saveCompanionPreferences(controller);
      controller.setAnimationsEnabled(false);
      final second = saveCompanionPreferences(controller);
      await Future.wait([first, second]);
      await restoreCompanionPreferences(restored);
      expect(restored.visible, isFalse);
      expect(restored.animationsEnabled, isFalse);
    },
  );

  test(
    'portrait and landscape uploads retain their aspect ratio and padding',
    () async {
      for (final size in [const Size(16, 32), const Size(32, 16)]) {
        final recorder = ui.PictureRecorder();
        Canvas(
          recorder,
        ).drawRect(Offset.zero & size, Paint()..color = Colors.red);
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          size.width.toInt(),
          size.height.toInt(),
        );
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final pixels = await PixelateProcessor.pixelate(
          bytes.buffer.asUint8List(),
        );
        image.dispose();
        picture.dispose();
        expect(pixels.length, 4096);
        expect(pixels.where((p) => p != 0).length, 32 * 64);
        expect(pixels.first, 0);
        expect(pixels[32 * 64 + 32], isNot(0));
      }
    },
  );

  testWidgets(
    'live controller really reaches the painter and respects frame duration and pause',
    (tester) async {
      final controller = PixelCompanionController();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: PixelCompanionLive(controller: controller)),
        ),
      );
      SpriteFrame paintedFrame() {
        final custom = tester.widget<CustomPaint>(
          find
              .descendant(
                of: find.byType(PixelCompanion),
                matching: find.byType(CustomPaint),
              )
              .first,
        );
        return (custom.painter as dynamic).frame as SpriteFrame;
      }

      controller.setStateExt(CompanionState.thinking);
      await tester.pump();
      expect(
        tester.widget<PixelCompanion>(find.byType(PixelCompanion)).state,
        CompanionState.thinking,
      );
      final first = paintedFrame();
      await tester.pump(const Duration(milliseconds: 200));
      expect(paintedFrame(), same(first));
      await tester.pump(const Duration(milliseconds: 500));
      expect(paintedFrame(), isNot(same(first)));
      controller.setAnimationsEnabled(false);
      await tester.pump();
      final still = paintedFrame();
      await tester.pump(const Duration(seconds: 5));
      expect(paintedFrame(), same(still));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('system reduce-motion leaves no active frame animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Center(child: PixelCompanion()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'new bubbles survive an older dismiss and disposal cancels all timers',
    (tester) async {
      final controller = CompanionBubbleController();
      controller.info('旧提示');
      controller.hide();
      await tester.pump(const Duration(milliseconds: 200));
      controller.info('新提示');
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.state.message!.text, '新提示');
      expect(controller.state.visible, isTrue);
      controller.hide();
      controller.dispose();
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings are reachable, persist toggles and fit a short scaled viewport',
    (tester) async {
      tester.view.physicalSize = const Size(700, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = PixelCompanionController();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.4)),
                  child: child!,
                ),
            home: Builder(
              builder:
                  (context) => Scaffold(
                    body: TextButton(
                      onPressed:
                          () => showCompanionSettingsSheet(context, controller),
                      child: const Text('打开伙伴'),
                    ),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开伙伴'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('播放角色动画'));
      await tester.tap(find.text('播放角色动画'));
      await tester.pump();
      expect(controller.animationsEnabled, isFalse);
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final restored = PixelCompanionController();
      await restoreCompanionPreferences(restored);
      expect(restored.animationsEnabled, isFalse);
      restored.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preview scrolls on short screens and stops its loop on exit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PixelCompanionController()..setAnimationsEnabled(false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          companionControllerProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp(
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.4)),
                child: child!,
              ),
          home: const CompanionPreviewPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('缩放:'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('自动循环所有状态'));
    await tester.pump(const Duration(milliseconds: 1800));
    expect(controller.state, CompanionState.speaking);
    await tester.tap(find.byTooltip('停止自动循环'));
    await tester.pump(const Duration(seconds: 2));
    expect(controller.state, CompanionState.speaking);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });
}
