import 'package:flutter/material.dart';

/// Tokens de cor da marca (alinhados com o design de referência BirthdayFlow:
/// coral quente + lavanda sobre um fundo creme).
class AppColors {
  const AppColors._();

  // Claro
  static const background = Color(0xFFFCF8F5);
  static const foreground = Color(0xFF281C1A);
  static const card = Color(0xFFFFFFFF);
  static const primary = Color(0xFFF05560);
  static const primaryForeground = Color(0xFFFFFBF7);
  static const secondary = Color(0xFFAB8BE3);
  static const muted = Color(0xFFF5F1EC);
  static const mutedForeground = Color(0xFF746560);
  static const accent = Color(0xFFF8EAF3);
  static const accentForeground = Color(0xFF7B252B);
  static const success = Color(0xFF37C080);
  static const destructive = Color(0xFFDF2225);
  static const border = Color(0xFFE9E3DF);
  static const amber = Color(0xFFF4A25C);
  static const blue = Color(0xFF418AD1);
  static const pink = Color(0xFFE662A8);

  // Escuro
  static const darkBackground = Color(0xFF191210);
  static const darkForeground = Color(0xFFF4EDE8);
  static const darkCard = Color(0xFF241C19);
  static const darkPrimary = Color(0xFFFA686A);
  static const darkPrimaryForeground = Color(0xFF150A08);
  static const darkSecondary = Color(0xFF9F7ED6);
  static const darkMuted = Color(0xFF2F2724);
  static const darkMutedForeground = Color(0xFFA99B94);
  static const darkAccent = Color(0xFF3E2D38);
  static const darkAccentForeground = Color(0xFFF8DED9);
  static const darkDestructive = Color(0xFFE64343);
  static const darkBorder = Color(0x1AFFFFFF);

  /// Paleta usada para categorias e avatares sem fotografia.
  static const swatches = <Color>[primary, secondary, success, amber, blue, pink];

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, pink, secondary],
  );
}

/// Cores semânticas extra que o [ColorScheme] do Material não cobre.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.accentForeground,
    required this.success,
    required this.border,
    required this.card,
    required this.softGradient,
  });

  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color accentForeground;
  final Color success;
  final Color border;
  final Color card;
  final Gradient softGradient;

  static const light = AppPalette(
    muted: AppColors.muted,
    mutedForeground: AppColors.mutedForeground,
    accent: AppColors.accent,
    accentForeground: AppColors.accentForeground,
    success: AppColors.success,
    border: AppColors.border,
    card: AppColors.card,
    softGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFF1F1), Color(0xFFFFF0F7), Color(0xFFF7F2FF)],
    ),
  );

  static const dark = AppPalette(
    muted: AppColors.darkMuted,
    mutedForeground: AppColors.darkMutedForeground,
    accent: AppColors.darkAccent,
    accentForeground: AppColors.darkAccentForeground,
    success: AppColors.success,
    border: AppColors.darkBorder,
    card: AppColors.darkCard,
    softGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF492828), Color(0xFF422733), Color(0xFF372D49)],
    ),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      muted: Color.lerp(muted, other.muted, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentForeground: Color.lerp(accentForeground, other.accentForeground, t)!,
      success: Color.lerp(success, other.success, t)!,
      border: Color.lerp(border, other.border, t)!,
      card: Color.lerp(card, other.card, t)!,
      softGradient: t < 0.5 ? softGradient : other.softGradient,
    );
  }
}

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
