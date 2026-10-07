import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  const AppTheme._();

  static const radius = 16.0;
  static const radiusSmall = 12.0;

  static ThemeData light() => _build(
    brightness: Brightness.light,
    background: AppColors.background,
    foreground: AppColors.foreground,
    card: AppColors.card,
    primary: AppColors.primary,
    onPrimary: AppColors.primaryForeground,
    secondary: AppColors.secondary,
    error: AppColors.destructive,
    palette: AppPalette.light,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    background: AppColors.darkBackground,
    foreground: AppColors.darkForeground,
    card: AppColors.darkCard,
    primary: AppColors.darkPrimary,
    onPrimary: AppColors.darkPrimaryForeground,
    secondary: AppColors.darkSecondary,
    error: AppColors.darkDestructive,
    palette: AppPalette.dark,
  );

  /// Títulos editoriais em serifa, como no site de referência.
  static TextStyle display(BuildContext context, {double size = 28, Color? color}) => GoogleFonts.fraunces(
    fontSize: size,
    fontWeight: FontWeight.w500,
    height: 1.15,
    letterSpacing: -0.4,
    color: color ?? Theme.of(context).colorScheme.onSurface,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color foreground,
    required Color card,
    required Color primary,
    required Color onPrimary,
    required Color secondary,
    required Color error,
    required AppPalette palette,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: palette.accent,
      onPrimaryContainer: palette.accentForeground,
      secondary: secondary,
      onSecondary: isDark ? AppColors.darkPrimaryForeground : Colors.white,
      secondaryContainer: palette.muted,
      onSecondaryContainer: foreground,
      tertiary: AppColors.success,
      onTertiary: Colors.white,
      error: error,
      onError: Colors.white,
      surface: background,
      onSurface: foreground,
      onSurfaceVariant: palette.mutedForeground,
      surfaceContainerLowest: card,
      surfaceContainerLow: card,
      surfaceContainer: card,
      surfaceContainerHigh: palette.muted,
      surfaceContainerHighest: palette.muted,
      outline: palette.border,
      outlineVariant: palette.border,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      base.textTheme,
    ).apply(bodyColor: foreground, displayColor: foreground);

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSmall),
      borderSide: BorderSide(color: palette.border),
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme.copyWith(
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20),
        titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 16),
        titleSmall: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.45),
        labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      extensions: [palette],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 17),
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: palette.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: palette.border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: TextStyle(color: palette.mutedForeground.withValues(alpha: 0.7)),
        labelStyle: TextStyle(color: palette.mutedForeground),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: primary, width: 1.6)),
        errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: error)),
        focusedErrorBorder: inputBorder.copyWith(borderSide: BorderSide(color: error, width: 1.6)),
        prefixIconColor: palette.mutedForeground,
        suffixIconColor: palette.mutedForeground,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall + 2)),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: foreground,
          side: BorderSide(color: palette.border),
          backgroundColor: card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall + 2)),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: palette.accent,
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: foreground),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: palette.accentForeground,
        ),
        checkmarkColor: palette.accentForeground,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: palette.accent,
        height: 68,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 11.5,
            color: states.contains(WidgetState.selected) ? foreground : palette.mutedForeground,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected) ? palette.accentForeground : palette.mutedForeground,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius + 2)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: palette.border,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.darkForeground : AppColors.foreground,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isDark ? AppColors.darkBackground : AppColors.background,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? onPrimary : palette.mutedForeground,
        ),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : palette.muted),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: palette.mutedForeground.withValues(alpha: 0.5), width: 1.5),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.mutedForeground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary, linearTrackColor: palette.muted),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.all(BorderSide(color: palette.border)),
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? foreground : card),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? background : foreground,
          ),
          textStyle: WidgetStateProperty.all(
            textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
