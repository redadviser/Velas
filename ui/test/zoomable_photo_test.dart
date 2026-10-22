import 'package:aniversarios/core/theme/app_theme.dart';
import 'package:aniversarios/features/chat/chat_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, String? url) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: ZoomablePhoto(url: url, title: 'Gil Costa', child: const SizedBox.square(dimension: 88, child: Text('avatar'))),
        ),
      ),
    ),
  );

  testWidgets('tocar na fotografia abre-a em ecrã inteiro', (tester) async {
    // Um caminho local: o ChatImage mostra-o sem ir à rede (aqui não existe, fica o fundo).
    await pump(tester, '/nao/existe.jpg');
    await tester.tap(find.text('avatar'));
    await tester.pumpAndSettle();
    expect(find.text('Gil Costa'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('sem fotografia não abre nada', (tester) async {
    await pump(tester, null);
    await tester.tap(find.text('avatar'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });
}
