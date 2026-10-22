import 'package:aniversarios/core/i18n/translations.dart';
import 'package:aniversarios/core/theme/app_colors.dart';
import 'package:aniversarios/data/models/group_models.dart';
import 'package:aniversarios/data/models/payment.dart';
import 'package:aniversarios/features/groups/payment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting();
    await Translations.load(const Locale('pt'));
  });

  test('cartão vem do Revolut ou do PayPal; Skrill pelo email', () {
    const onlyMbway = PaymentDetails(mbwayPhone: '912345678', acceptsCash: false);
    expect(onlyMbway.methods, [PaymentMethod.mbway]);
    expect(onlyMbway.acceptsCard, isFalse);

    const all = PaymentDetails(mbwayPhone: '912345678', revolutTag: 'ana', paypalUser: 'ana', skrillEmail: 'ana@ex.pt');
    expect(all.methods, PaymentMethod.values);
    expect(const PaymentDetails(paypalUser: 'ana').acceptsCard, isTrue);
    expect(PaymentDetails.fromJson(all.toJson()).skrillEmail, 'ana@ex.pt');
    expect(PaymentFormat.normalizeEmail(' Ana@Ex.PT '), 'ana@ex.pt');
    expect(PaymentFormat.normalizeEmail('ana@'), isNull);
    expect(PaymentMethod.tryParse('skrill'), PaymentMethod.skrill);
    expect(PaymentMethod.card.label, 'Cartão');
  });

  Future<PayResult? Function()> open(WidgetTester tester, PaymentDetails payee) async {
    PayResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.light]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPaySheet(
                  context,
                  payeeName: 'Ana',
                  amount: 15,
                  payee: payee,
                  reference: 'Prenda — Eu',
                );
              },
              child: const Text('pagar'),
            ),
          ),
        ),
      ),
    );
    return () => result;
  }

  testWidgets('escolher o método e registar o pagamento', (tester) async {
    tester.view
      ..physicalSize = const Size(402, 874) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final result = await open(tester, const PaymentDetails(mbwayPhone: '912345678', revolutTag: 'ana'));
    await tester.tap(find.text('pagar'));
    await tester.pumpAndSettle();

    expect(find.text('Pagar a Ana'), findsOneWidget);
    // Todos os métodos aparecem; os que a Ana não indicou ficam indisponíveis.
    for (final label in ['Cartão', 'MB WAY', 'PayPal', 'Skrill', 'Revolut', 'Dinheiro']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Não disponível'), findsNWidgets(2)); // PayPal, Skrill
    expect(find.text('Transferência'), findsNothing);
    // O cartão (pelo Revolut) vem escolhido primeiro.
    expect(find.textContaining('com cartão'), findsOneWidget); // "Pagar 15 € com cartão"
    expect(find.textContaining('não precisas de conta Revolut'), findsOneWidget);

    // Um indisponível só explica porquê.
    await tester.tap(find.text('Skrill'));
    await tester.pumpAndSettle();
    expect(find.text('Ana não indicou este método.'), findsOneWidget);

    await tester.tap(find.text('MB WAY'));
    await tester.pumpAndSettle();
    expect(find.text('912 345 678'), findsOneWidget);
    expect(find.text('Copiar número'), findsOneWidget);

    await tester.tap(find.text('Já paguei por MB WAY'));
    await tester.pumpAndSettle();
    expect(result()?.method, PaymentMethod.mbway);
    expect(result()?.paidInApp, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sem dados de pagamento, explica e deixa pagar em mão', (tester) async {
    tester.view
      ..physicalSize = const Size(375, 667) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await open(tester, PaymentDetails.empty);
    await tester.tap(find.text('pagar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ana ainda não indicou'), findsOneWidget);
    expect(find.text('Já paguei por Dinheiro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('grupo traz a fotografia do servidor e mantém-na ao editar', () {
    final g = GiftGroup.fromJson({
      'id': 'g',
      'created_by': 'me',
      'title': 'Prenda',
      'celebrant_name': 'Rui',
      'target_amount': 20,
      'photo_url': 'https://api.test/files/g/photo-1.jpg',
    });
    expect(g.photoUrl, isNotNull);
    expect(g.copyWith(title: 'Outra').photoUrl, g.photoUrl);
  });
}
