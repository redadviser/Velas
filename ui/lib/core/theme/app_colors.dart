import 'package:flutter/material.dart';

/// Tokens de cor da marca: coral sobre creme, com violeta e amarelo de apoio.
/// O coral de texto e botões é mais escuro que o da marca para cumprir AA.
class AppColors {
  const AppColors._();

  // Claro
  static const background = Color(0xFFFBF8F3);
  static const foreground = Color(0xFF29252D);
  static const card = Color(0xFFFFFFFF);
  static const brand = Color(0xFFE84F6B);
  static const primary = Color(0xFFCF3557);
  static const primaryForeground = Color(0xFFFFFFFF);
  static const secondary = Color(0xFF7461D8);
  static const muted = Color(0xFFF5F1EB);
  static const mutedForeground = Color(0xFF6F6873);
  static const accent = Color(0xFFFFF0F2);
  static const accentForeground = Color(0xFFC42F50);
  static const success = Color(0xFF258A6B);
  static const destructive = Color(0xFFD32F2F);
  static const border = Color(0xFFEBE5DF);
  static const amber = Color(0xFFF2B33D);
  static const blue = Color(0xFF3F82C4);
  static const pink = Color(0xFFE662A8);
  static const violetSoft = Color(0xFFF0EDFF);

  // Escuro
  static const darkBackground = Color(0xFF17151A);
  static const darkForeground = Color(0xFFF7F1F3);
  static const darkCard = Color(0xFF211E25);
  static const darkPrimary = Color(0xFFEE5D78);
  static const darkPrimaryForeground = Color(0xFF1C0A10);
  static const darkSecondary = Color(0xFF9A8AF0);
  static const darkMuted = Color(0xFF2B2730);
  static const darkMutedForeground = Color(0xFFB9B1BC);
  static const darkAccent = Color(0xFF3B222B);
  static const darkAccentForeground = Color(0xFFFFC2CE);
  static const darkDestructive = Color(0xFFEF5350);
  static const darkBorder = Color(0xFF3A343E);
  static const darkVioletSoft = Color(0xFF2C283B);

  /// Paleta usada para categorias e avatares sem fotografia.
  static const swatches = <Color>[brand, secondary, success, amber, blue, pink];

  /// Fundo e letra dos avatares sem foto, pela mesma ordem de [swatches].
  static const tones = <(Color, Color)>[
    (Color(0xFFFFD7DF), Color(0xFF8D3547)),
    (Color(0xFFDDD7FF), Color(0xFF5B49AA)),
    (Color(0xFFD3EEE2), Color(0xFF22684F)),
    (Color(0xFFFFE4A5), Color(0xFF7A570C)),
    (Color(0xFFD6E8FB), Color(0xFF35648F)),
    (Color(0xFFFADCEB), Color(0xFF8E2F62)),
  ];

  static const brandGradient = LinearGradient(
    begin: Alignment(-1, -0.8),
    end: Alignment(1, 0.8),
    colors: [Color(0xFFD43A5B), Color(0xFFBF2D4C)],
  );
}

/// Temas da app (Birthdayly+): a cor principal e o gradiente da marca. O resto
/// da paleta (fundos, texto, bordas) é igual em todos.
enum AppAccent {
  coral('Coral', AppColors.primary, AppColors.darkPrimary, [Color(0xFFD43A5B), Color(0xFFBF2D4C)]),
  lavanda('Lavanda', Color(0xFF8B6FD6), Color(0xFFA58BEA), [Color(0xFF8B6FD6), Color(0xFFB57FE0), Color(0xFFE662A8)]),
  oceano('Oceano', Color(0xFF2F86D1), Color(0xFF5AA6E8), [Color(0xFF2F86D1), Color(0xFF3BB3C3), Color(0xFF6ED3B0)]),
  menta('Menta', Color(0xFF23A078), Color(0xFF45C497), [Color(0xFF23A078), Color(0xFF7CC46B), Color(0xFFF4C35C)]);

  const AppAccent(this.label, this.light, this.dark, this.gradient);

  final String label;
  final Color light;
  final Color dark;
  final List<Color> gradient;

  LinearGradient get brand =>
      LinearGradient(begin: const Alignment(-1, -0.8), end: const Alignment(1, 0.8), colors: gradient);
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
    required this.violetSoft,
    required this.shadow,
    this.brand = AppColors.brandGradient,
  });

  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color accentForeground;
  final Color success;
  final Color border;
  final Color card;
  final Gradient softGradient;

  /// Fundo de cartões de festa, convites e recolha por link.
  final Color violetSoft;

  /// Sombra suave dos cartões em relevo.
  final List<BoxShadow> shadow;

  /// O gradiente da marca no tema escolhido (ver [AppAccent]).
  final LinearGradient brand;

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
      colors: [Color(0xFFFFF4F1), Color(0xFFFFF0F2), Color(0xFFF3F0FF)],
    ),
    violetSoft: AppColors.violetSoft,
    shadow: [BoxShadow(color: Color(0x1452393E), blurRadius: 30, offset: Offset(0, 10))],
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
      colors: [Color(0xFF3B222B), Color(0xFF33232F), Color(0xFF2C283B)],
    ),
    violetSoft: AppColors.darkVioletSoft,
    shadow: [BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 12))],
  );

  @override
  AppPalette copyWith({LinearGradient? brand, Color? mutedForeground, Color? border}) => AppPalette(
    muted: muted,
    mutedForeground: mutedForeground ?? this.mutedForeground,
    accent: accent,
    accentForeground: accentForeground,
    success: success,
    border: border ?? this.border,
    card: card,
    softGradient: softGradient,
    violetSoft: violetSoft,
    shadow: shadow,
    brand: brand ?? this.brand,
  );

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
      violetSoft: Color.lerp(violetSoft, other.violetSoft, t)!,
      shadow: BoxShadow.lerpList(shadow, other.shadow, t)!,
      brand: LinearGradient.lerp(brand, other.brand, t)!,
    );
  }
}

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
