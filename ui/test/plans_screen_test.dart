import 'dart:convert';

import 'package:aniversarios/core/i18n/translations.dart';
import 'package:aniversarios/core/providers.dart';
import 'package:aniversarios/core/theme/app_theme.dart';
import 'package:aniversarios/data/api/api_client.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/data/repositories/auth_repository.dart';
import 'package:aniversarios/features/profile/plans_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const me = UserProfile(id: 'me', email: 'eu@ex.pt', name: 'Eu');

class FakeAuth implements AuthRepository {
  var trials = 0;

  @override
  Future<void> startPlusTrial() async => trials++;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Translations.load(const Locale('pt'));
  });

  test('o anual poupa 33% face a 12 meses', () {
    expect(PlusPricing.yearlySavingPercent, 33);
  });

  testWidgets('mostra os dois planos e regista o interesse no Birthdayly+', (tester) async {
    // A letra dos testes desenha cada carácter como um quadrado (mais larga do
    // que a da app), por isso o ecrã de teste é um pouco mais largo que um telemóvel.
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'velas.api.refreshToken': 'r1'});
    final sent = <Object?>[];
    final api = ApiClient(
      'https://api.test',
      client: MockClient((req) async {
        if (req.url.path == '/auth/refresh') {
          return http.Response(jsonEncode({'access_token': 'a', 'refresh_token': 'r2', 'user': {'id': 'me'}}), 200);
        }
        sent.add(jsonDecode(req.body));
        return http.Response('', 204);
      }),
    );
    await api.restore();
    final prefs = await SharedPreferences.getInstance();
    final auth = FakeAuth();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(me),
          apiClientProvider.overrideWithValue(api),
          sharedPrefsProvider.overrideWithValue(prefs),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const PlansScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Grátis'), findsOneWidget);
    expect(find.text('O teu plano'), findsOneWidget);
    expect(find.textContaining('19,99 €'), findsOneWidget);
    expect(find.textContaining('poupas 33%'), findsOneWidget);

    await tester.tap(find.text('Mensal'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2,49 €'), findsOneWidget);

    // Sem o plano e com o período experimental por usar, o botão principal é experimentar.
    await tester.tap(find.text('Experimentar 30 dias grátis'));
    await tester.pumpAndSettle();
    expect(auth.trials, 1);

    await tester.tap(find.text('Avisa-me quando a subscrição chegar'));
    await tester.pumpAndSettle();
    expect(sent, [
      {'plan': 'monthly'},
    ]);
    expect(find.text('Vais ser dos primeiros a saber.'), findsOneWidget);
    expect(prefs.getString('velas.plusInterest.me'), 'monthly');
  });
}
