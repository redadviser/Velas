import 'package:aniversarios/core/i18n/translations.dart';
import 'package:aniversarios/core/theme/app_colors.dart';
import 'package:aniversarios/data/models/payment.dart';
import 'package:aniversarios/data/models/payments_models.dart';
import 'package:aniversarios/features/groups/payment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

const payee = PaymentDetails(
  inApp: true,
  inAppFees: {
    'card': (percent: 1.5, fixed: 0.25),
    'mb_way': (percent: 1.5, fixed: 0.25),
    'paypal': (percent: 3.4, fixed: 0.35),
  },
);

InAppPayment payment(String status, {String method = 'mb_way', String? error, String? url}) => InAppPayment(
  id: 'p1',
  method: method,
  amount: 13.33,
  fee: 0.46,
  total: 13.79,
  status: status,
  error: error,
  checkoutUrl: url,
);

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting();
    await Translations.load(const Locale('pt'));
  });

  test('a comissão é somada como no servidor', () {
    expect(payee.withFee(PaymentMethod.card, 13.33), (fee: 0.46, total: 13.79));
    expect(payee.withFee(PaymentMethod.cash, 13.33), (fee: 0.0, total: 13.33));
    // Com a taxa de serviço da Birthdayly (0,39 €), igual ao servidor: (13,33 + 0,25 + 0,39) / 0,985.
    final withService = PaymentDetails.fromJson({
      'in_app': true,
      'in_app_fees': {'mb_way': {'percent': 1.5, 'fixed': 0.25}},
      'in_app_service_fee': 0.39,
    });
    expect(withService.withFee(PaymentMethod.mbway, 13.33), (fee: 0.86, total: 14.19));
    // Com a conta Stripe de quem recebe, cartão, PayPal e MB WAY pagam-se na app sem mais dados.
    expect(payee.methods, [
      PaymentMethod.card,
      PaymentMethod.mbway,
      PaymentMethod.paypal,
      PaymentMethod.revolut,
      PaymentMethod.transfer,
      PaymentMethod.cash,
    ]);
    expect(payee.payInApp(PaymentMethod.mbway), isTrue);
    expect(payee.payInApp(PaymentMethod.transfer), isTrue); // IBAN na página da Stripe (débito SEPA)
    expect(payee.payInApp(PaymentMethod.skrill), isFalse);
    expect(PaymentMethod.transfer.inAppName, 'sepa_debit');
    expect(PaymentMethod.revolut.inAppName, 'revolut_pay');
    expect(PaymentFormat.toE164('912 345 678'), '+351912345678');
    expect(PaymentFormat.displayE164('+351912345678'), '912 345 678');
  });

  Future<PayResult? Function()> open(WidgetTester tester, InAppPay inApp) async {
    tester.view
      ..physicalSize = const Size(402, 874) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    PayResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.light]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showPaySheet(
                context,
                payeeName: 'Bia',
                amount: 13.33,
                payee: payee,
                reference: 'Prenda — Caio',
                inApp: inApp,
              ),
              child: const Text('pagar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('pagar'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('MB WAY: pede o número, associa-o e fecha quando é aprovado', (tester) async {
    final starts = <(PaymentMethod, String?, bool)>[];
    var status = 'pending';
    final result = await open(
      tester,
      InAppPay(
        start: (m, {phone, savePhone = false}) async {
          starts.add((m, phone, savePhone));
          return payment('pending');
        },
        poll: (_) async => payment(status),
      ),
    );

    // Cartão vem primeiro, com a comissão à vista e sem "Já paguei" (é automático).
    expect(find.text('Pagar na app'), findsOneWidget);
    expect(find.textContaining('de comissão'), findsOneWidget);
    expect(find.textContaining('Já paguei'), findsNothing);

    await tester.tap(find.text('MB WAY'));
    await tester.pumpAndSettle();
    expect(find.text('Associar este número para próximos pagamentos'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '91234');
    await tester.ensureVisible(find.textContaining('Enviar pedido'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Enviar pedido'));
    await tester.pumpAndSettle();
    expect(find.text('Número de telemóvel inválido.'), findsOneWidget);
    expect(starts, isEmpty);

    await tester.enterText(find.byType(TextField), '912 345 678');
    await tester.ensureVisible(find.textContaining('Enviar pedido'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Enviar pedido'));
    await tester.pump();
    await tester.pump();
    expect(starts.single, (PaymentMethod.mbway, '+351912345678', true));
    expect(find.textContaining('aprova o pedido'), findsOneWidget);

    status = 'succeeded';
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(result()?.paidInApp, isTrue);
    expect(result()?.method, PaymentMethod.mbway);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transferência: autorizada fica a caminho e a janela fecha', (tester) async {
    final methods = <PaymentMethod>[];
    final result = await open(
      tester,
      InAppPay(
        start: (m, {phone, savePhone = false}) async {
          methods.add(m);
          return payment('pending', method: 'sepa_debit', url: 'https://checkout.stripe.test/sepa_debit');
        },
        poll: (_) async => payment('processing', method: 'sepa_debit'),
      ),
    );
    await tester.tap(find.text('Transferência'));
    await tester.pumpAndSettle();
    expect(find.textContaining('IBAN na página segura da Stripe'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('Transferir'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Transferir'));
    await tester.pump();
    await tester.pump();
    expect(methods, [PaymentMethod.transfer]);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(result()?.paidInApp, isTrue);
    expect(result()?.processing, isTrue);
  });

  testWidgets('MB WAY com número associado usa-o; recusado explica porquê', (tester) async {
    final starts = <(String?, bool)>[];
    await open(
      tester,
      InAppPay(
        savedPhone: '+351936000111',
        start: (m, {phone, savePhone = false}) async {
          starts.add((phone, savePhone));
          return payment('failed', error: 'payment_method_customer_decline');
        },
        poll: (_) async => payment('failed'),
      ),
    );
    await tester.tap(find.text('MB WAY'));
    await tester.pumpAndSettle();
    expect(find.text('936 000 111'), findsOneWidget);
    expect(find.text('Usar outro número'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('Enviar pedido'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Enviar pedido'));
    await tester.pumpAndSettle();
    expect(starts.single, (null, false)); // o servidor usa o número guardado
    expect(find.text('O pagamento foi recusado.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
