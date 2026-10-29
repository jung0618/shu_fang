// =============================================================================
// ShuFang Design System — Theme Assembly
// =============================================================================
// 组合 colors / typography / spacing / motion / elevation 形成统一 ThemeData。
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colors.dart';
import 'radius.dart';
import 'typography.dart';

class AppTheme {
  AppTheme._();

  /// 亮色主题 — 暖白纸张感。
  static ThemeData get light => _build(Brightness.light);

  /// 暗色主题 — 暖灰背景。
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? AppColors.primary : AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: isDark
          ? const Color(0xFF1B2C4A)
          : AppColors.primaryContainer,
      onPrimaryContainer: isDark
          ? const Color(0xFFC9D8F7)
          : AppColors.onPrimaryContainer,
      secondary: isDark ? AppColors.ai : AppColors.ai,
      onSecondary: Colors.white,
      secondaryContainer: isDark
          ? const Color(0xFF2A1F4A)
          : AppColors.aiContainer,
      onSecondaryContainer: isDark
          ? const Color(0xFFDCC9F7)
          : AppColors.onAiContainer,
      tertiary: AppColors.success,
      onTertiary: Colors.white,
      tertiaryContainer: isDark
          ? const Color(0xFF0E3A2C)
          : AppColors.successContainer,
      onTertiaryContainer: isDark
          ? const Color(0xFFC4EDDB)
          : AppColors.onSuccessContainer,
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: isDark
          ? const Color(0xFF3F1818)
          : AppColors.errorContainer,
      onErrorContainer: isDark
          ? const Color(0xFFF5CDCB)
          : AppColors.onErrorContainer,
      surface: isDark ? AppColors.darkSurface : Colors.white,
      onSurface: isDark
          ? AppColors.darkTextPrimary
          : AppColors.neutral900,
      surfaceContainerLowest: isDark
          ? AppColors.darkBg
          : AppColors.neutral50,
      surfaceContainerLow: isDark
          ? AppColors.darkSurface
          : AppColors.neutral50,
      surfaceContainer: isDark
          ? AppColors.darkSurfaceHigh
          : AppColors.neutral100,
      surfaceContainerHigh: isDark
          ? AppColors.darkSurfaceHigh
          : AppColors.neutral150,
      surfaceContainerHighest: isDark
          ? AppColors.darkSurfaceHighest
          : AppColors.neutral200,
      onSurfaceVariant: isDark
          ? AppColors.darkTextSecondary
          : AppColors.neutral600,
      outline: isDark ? AppColors.darkBorder : AppColors.neutral300,
      outlineVariant: isDark
          ? const Color(0xFF2C2925)
          : AppColors.neutral200,
      shadow: isDark ? Colors.black : const Color(0xFF1F1A14),
      scrim: isDark ? Colors.black87 : const Color(0x661F1A14),
      inverseSurface: isDark
          ? AppColors.neutral100
          : AppColors.neutral800,
      onInverseSurface: isDark
          ? AppColors.neutral900
          : AppColors.darkTextPrimary,
      inversePrimary: isDark
          ? AppColors.primary
          : const Color(0xFFADC6FF),
      surfaceTint: AppColors.primary,
    );

    final textTheme = AppTypography.toTextTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppPalette.scaffold(brightness),
      canvasColor: AppPalette.surface(brightness),
      textTheme: textTheme,
      fontFamily: 'system-ui',
      splashFactory: InkSparkle.splashFactory,
      // -------------------- 视觉密度 --------------------
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // -------------------- AppBar --------------------
      appBarTheme: AppBarTheme(
        backgroundColor: AppPalette.surface(brightness),
        foregroundColor: AppPalette.textPrimary(brightness),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: AppColors.darkBg,
                systemNavigationBarIconBrightness: Brightness.light,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: AppColors.neutral50,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(
          color: AppPalette.textSecondary(brightness),
          size: 20,
        ),
        actionsIconTheme: IconThemeData(
          color: AppPalette.textSecondary(brightness),
          size: 20,
        ),
      ),
      // -------------------- 卡片 --------------------
      cardTheme: CardThemeData(
        color: AppPalette.surface(brightness),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
          side: BorderSide(color: AppPalette.border(brightness), width: 1),
        ),
      ),
      // -------------------- 按钮 --------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.sm),
          ),
          textStyle: AppTypography.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          side: BorderSide(color: AppPalette.border(brightness), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.sm),
          ),
          textStyle: AppTypography.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.xs),
          ),
          textStyle: AppTypography.labelLarge,
        ),
      ),
      // -------------------- 输入框 --------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppPalette.surfaceHigh(brightness),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: AppPalette.border(brightness), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: AppPalette.border(brightness), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: scheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: AppPalette.textTertiary(brightness),
        ),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: AppPalette.textSecondary(brightness),
        ),
      ),
      // -------------------- 列表项 --------------------
      listTileTheme: ListTileThemeData(
        iconColor: AppPalette.textSecondary(brightness),
        textColor: AppPalette.textPrimary(brightness),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minLeadingWidth: 20,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.xs),
        ),
        titleTextStyle: textTheme.bodyMedium,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: AppPalette.textSecondary(brightness),
        ),
      ),
      // -------------------- Chip --------------------
      chipTheme: ChipThemeData(
        backgroundColor: AppPalette.surfaceHigh(brightness),
        side: BorderSide(color: AppPalette.border(brightness), width: 1),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.pill),
        ),
        selectedColor: scheme.primaryContainer,
      ),
      // -------------------- 对话框 --------------------
      dialogTheme: DialogThemeData(
        backgroundColor: AppPalette.surface(brightness),
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.lg),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      // -------------------- 底表 --------------------
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppPalette.surface(brightness),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(R.xl)),
        ),
      ),
      // -------------------- 抽屉 --------------------
      drawerTheme: DrawerThemeData(
        backgroundColor: AppPalette.surface(brightness),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(R.lg)),
        ),
      ),
      // -------------------- Tooltip --------------------
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.neutral800
              : AppColors.neutral900.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(R.xs),
        ),
        textStyle: textTheme.labelSmall?.copyWith(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 400),
      ),
      // -------------------- TabBar --------------------
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: AppPalette.textSecondary(brightness),
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
        dividerColor: AppPalette.divider(brightness),
        overlayColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.06),
        ),
      ),
      // -------------------- 进度条 --------------------
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: AppPalette.surfaceHighest(brightness),
        circularTrackColor: AppPalette.surfaceHighest(brightness),
      ),
      // -------------------- Icon --------------------
      iconTheme: IconThemeData(
        color: AppPalette.textSecondary(brightness),
        size: 18,
      ),
      primaryIconTheme: IconThemeData(
        color: scheme.onPrimary,
        size: 18,
      ),
      // -------------------- Divider --------------------
      dividerTheme: DividerThemeData(
        color: AppPalette.divider(brightness),
        thickness: 1,
        space: 1,
      ),
      // -------------------- Snackbar --------------------
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark
            ? AppColors.darkSurfaceHighest
            : AppColors.neutral800,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: scheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.sm),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 6,
      ),
      // -------------------- 切换 --------------------
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return scheme.primary;
          return AppPalette.disabled(brightness);
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: 0.3);
          }
          return AppPalette.surfaceHighest(brightness);
        }),
      ),
    );
  }
}
