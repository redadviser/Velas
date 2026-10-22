import 'package:aniversarios/core/i18n/translations.dart';
import 'package:aniversarios/core/providers.dart';
import 'package:aniversarios/core/theme/app_colors.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/features/profile/payment_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Translations.load(const Locale('pt'));
  });

  Future<void> pump(WidgetTester tester, UserProfile user) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentUserProvider.overrideWithValue(user)],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppPalette.light]),
          home: const PaymentDetailsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String field(WidgetTester tester, int i) =>
      tester.widgetList<TextField>(find.byType(TextField)).elementAt(i).controller!.text;

  testWidgets('escolhe como prefere receber; o MB WAY vem do telemóvel da conta', (tester) async {
    await pump(tester, const UserProfile(id: 'me', email: 'eu@ex.pt', name: 'Eu', phone: '+351912345678'));
    expect(find.text('Pagamentos'), findsOneWidget);
    expect(find.textContaining('Escolhe como preferes receber'), findsOneWidget);
    for (final label in ['MB WAY', 'Revolut', 'PayPal.me', 'Skrill (email)']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Transferência bancária'), findsNothing);
    expect(field(tester, 0), '912 345 678');
    // Nada de "ligar conta Stripe".
    expect(find.textContaining('Stripe'), findsNothing);
  });

  testWidgets('mantém os dados já indicados', (tester) async {
    await pump(
      tester,
      const UserProfile(
        id: 'me',
        email: 'eu@ex.pt',
        name: 'Eu',
        phone: '+351912345678',
        payment: PaymentDetails(mbwayPhone: '936000111', revolutTag: 'eu'),
      ),
    );
    expect(field(tester, 0), '936 000 111');
    expect(field(tester, 1), 'eu');
  });
}
