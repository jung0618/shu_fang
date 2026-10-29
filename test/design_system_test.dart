// =============================================================================
// ShuFang Design System — Token Tests
// =============================================================================
// 验证设计 token 的值与一致性。
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shufang_flutter/theme/theme.dart';

void main() {
  group('Spacing tokens (S)', () {
    test('4px base grid is respected', () {
      expect(S.zero, 0);
      expect(S.xs, 4);
      expect(S.sm, 8);
      expect(S.md, 12);
      expect(S.lg, 16);
      expect(S.xl, 20);
      expect(S.xxl, 24);
      expect(S.xxxl, 32);
      expect(S.huge, 40);
      expect(S.giant, 56);
    });

    test('Each spacing is greater than the previous one', () {
      final chain = [
        S.xxs,
        S.xs,
        S.s,
        S.sm,
        S.md,
        S.lg,
        S.xl,
        S.xxl,
        S.xxxl,
        S.huge,
        S.giant,
      ];
      for (var i = 1; i < chain.length; i++) {
        expect(chain[i] > chain[i - 1], isTrue,
            reason: '${chain[i]} should be > ${chain[i - 1]}');
      }
    });
  });

  group('Radius tokens (R)', () {
    test('Have valid step ladder', () {
      expect(R.xxs, 1);
      expect(R.xs, 2);
      expect(R.sm, 4);
      expect(R.md, 6);
      expect(R.lg, 8);
      expect(R.xl, 12);
      expect(R.xxl, 16);
      expect(R.pill, 999);
    });

    test('Pill radius is a very large value for capsule shape', () {
      expect(R.pill > 100, isTrue);
    });
  });

  group('Color tokens (AppColors)', () {
    test('Primary color is defined', () {
      expect(AppColors.primary, isNotNull);
      expect(AppColors.primary, isA<Color>());
    });

    test('AI accent gradient colors are defined', () {
      expect(AppColors.aiGradientStart, isNotNull);
      expect(AppColors.aiGradientEnd, isNotNull);
    });

    test('Semantic colors are defined', () {
      expect(AppColors.success, isNotNull);
      expect(AppColors.warning, isNotNull);
      expect(AppColors.error, isNotNull);
      expect(AppColors.info, isNotNull);
    });

    test('Neutral scale is monotonic in lightness', () {
      // 白 → 黑 11 阶，每一档应比上一档暗（HSL 亮度）
      final neutrals = [
        AppColors.neutral50,
        AppColors.neutral100,
        AppColors.neutral150,
        AppColors.neutral200,
        AppColors.neutral300,
        AppColors.neutral400,
        AppColors.neutral500,
        AppColors.neutral600,
        AppColors.neutral700,
        AppColors.neutral800,
        AppColors.neutral900,
      ];
      double lum(Color c) {
        // 简单亮度 = R + G + B
        final r = (c.r * 255).round();
        final g = (c.g * 255).round();
        final b = (c.b * 255).round();
        return (r + g + b) / 3;
      }

      for (var i = 1; i < neutrals.length; i++) {
        expect(
          lum(neutrals[i]) < lum(neutrals[i - 1]),
          isTrue,
          reason: 'Neutral[$i] (${neutrals[i].value.toRadixString(16)}) '
              'must be darker than Neutral[${i - 1}] (${neutrals[i - 1].value.toRadixString(16)})',
        );
      }
    });
  });

  group('AppPalette theme-aware helpers', () {
    test('Returns different colors for light and dark', () {
      final lightScaffold = AppPalette.scaffold(Brightness.light);
      final darkScaffold = AppPalette.scaffold(Brightness.dark);
      expect(lightScaffold, isNot(equals(darkScaffold)));
    });

    test('Surface in light is white, in dark is warm gray', () {
      expect(AppPalette.surface(Brightness.light), Colors.white);
      expect(AppPalette.surface(Brightness.dark), AppColors.darkSurface);
    });

    test('Text colors differ in light vs dark', () {
      expect(
        AppPalette.textPrimary(Brightness.light),
        isNot(equals(AppPalette.textPrimary(Brightness.dark))),
      );
    });
  });

  group('Motion tokens (Motion)', () {
    test('Durations are in ascending order', () {
      expect(Motion.micro < Motion.fast, isTrue);
      expect(Motion.fast < Motion.medium, isTrue);
      expect(Motion.medium < Motion.slow, isTrue);
      expect(Motion.slow < Motion.entrance, isTrue);
    });

    test('Curves are valid Curves', () {
      expect(Motion.standard, isA<Curve>());
      expect(Motion.emphasized, isA<Curve>());
      expect(Motion.exit, isA<Curve>());
    });
  });

  group('AppTheme assembly', () {
    test('Light theme builds successfully', () {
      final theme = AppTheme.light;
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('Dark theme builds successfully', () {
      final theme = AppTheme.dark;
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('Themes provide complete visual density', () {
      expect(AppTheme.light.visualDensity, isNotNull);
      expect(AppTheme.dark.visualDensity, isNotNull);
    });
  });

  group('Typography', () {
    test('Type styles are non-null and have valid sizes', () {
      expect(AppTypography.displayLarge.fontSize, 32);
      expect(AppTypography.headlineLarge.fontSize, 24);
      expect(AppTypography.titleLarge.fontSize, 17);
      expect(AppTypography.bodyLarge.fontSize, 16);
      expect(AppTypography.labelLarge.fontSize, 13);
    });

    test('Body style uses serif for reading comfort', () {
      expect(AppTypography.bodyLarge.fontFamily, 'serif');
    });

    test('UI styles use system-ui for crispness', () {
      expect(AppTypography.titleLarge.fontFamily, 'system-ui');
      expect(AppTypography.labelMedium.fontFamily, 'system-ui');
    });

    test('Type theme conversion to TextTheme', () {
      final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary);
      final textTheme = AppTypography.toTextTheme(scheme);
      expect(textTheme.displayLarge, isNotNull);
      expect(textTheme.bodyLarge, isNotNull);
      expect(textTheme.labelMedium, isNotNull);
    });
  });
}
