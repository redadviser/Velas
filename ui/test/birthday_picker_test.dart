import 'package:aniversarios/core/theme/app_colors.dart';
import 'package:aniversarios/features/people/birthday_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('pt_PT');
    Intl.defaultLocale = 'pt_PT';
  });

  // Tamanhos lógicos do iPhone SE e do iPhone 17 Pro.
  for (final size in const [Size(375, 667), Size(402, 874)]) {
    testWidgets('o seletor de data cabe no ecrã ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view
        ..physicalSize = size * 3
        ..devicePixelRatio = 3
        ..padding = const FakeViewPadding(bottom: 34 * 3);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [AppPalette.light],
            bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
          ),
          home: Builder(
            builder: (context) => TextButton(onPressed: () => showBirthdayPicker(context), child: const Text('abrir')),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Confirmar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  Future<BirthDate? Function()> open(WidgetTester tester, {BirthDate? initial}) async {
    BirthDate? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.light]),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showBirthdayPicker(context, initial: initial),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('data nova: ano → mês → dia', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text('2020'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Março').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(result(), (day: 12, month: 3, year: 2020));
  });

  testWidgets('sem ano permite 29 de fevereiro', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text('Sem ano'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fevereiro').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('29'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(result(), (day: 29, month: 2, year: null));
  });

  testWidgets('ao editar abre no mês e ajusta o dia ao mudar de mês', (tester) async {
    final result = await open(tester, initial: (day: 31, month: 1, year: 1990));
    expect(find.text('Janeiro'), findsOneWidget);
    await tester.tap(find.byTooltip('Mês seguinte'));
    await tester.pumpAndSettle();
    expect(find.text('Fevereiro'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(result(), (day: 28, month: 2, year: 1990));
  });
}
