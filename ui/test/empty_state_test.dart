import 'package:aniversarios/core/theme/app_colors.dart';
import 'package:aniversarios/core/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget body) => MaterialApp(
    theme: ThemeData(extensions: const [AppPalette.light]),
    home: Scaffold(body: body),
  );
  const empty = EmptyState(icon: Icons.search, title: 'Sem resultados', message: 'Não encontrámos ninguém.');

  // Em Pessoas, um filtro sem resultados mostra o estado vazio no resto da lista.
  testWidgets('cabe num SliverFillRemaining sem rebentar', (tester) async {
    await tester.pumpWidget(
      app(const CustomScrollView(slivers: [SliverFillRemaining(hasScrollBody: false, child: empty)])),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Sem resultados'), findsOneWidget);
  });

  testWidgets('num ecrã baixo com letra grande, rola em vez de transbordar', (tester) async {
    tester.view.physicalSize = const Size(360, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Center(child: empty),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
