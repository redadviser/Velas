import 'dart:math';

import 'package:aniversarios/core/theme/app_colors.dart';
import 'package:aniversarios/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

double _contrast(Color a, Color b) {
  final (x, y) = (a.computeLuminance(), b.computeLuminance());
  return (max(x, y) + 0.05) / (min(x, y) + 0.05);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final accent in AppAccent.values) {
    for (final dark in [false, true]) {
      test('${accent.label} ${dark ? 'escuro' : 'claro'}: tons na cor do tema e texto AA', () {
        final theme = dark ? AppTheme.dark(accent: accent) : AppTheme.light(accent: accent);
        final p = theme.extension<AppPalette>()!;
        final coral = (dark ? AppTheme.dark() : AppTheme.light()).extension<AppPalette>()!;
        if (accent != AppAccent.coral) expect(p.accent, isNot(coral.accent));
        expect(_contrast(p.accentForeground, p.accent), greaterThanOrEqualTo(4.5));
      });
    }
  }
}
