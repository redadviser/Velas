import 'dart:convert';

import 'package:aniversarios/core/chat_providers.dart';
import 'package:aniversarios/core/i18n/translations.dart';
import 'package:aniversarios/core/providers.dart';
import 'package:aniversarios/core/theme/app_theme.dart';
import 'package:aniversarios/data/api/api_client.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/features/people/birthday_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const me = UserProfile(id: 'me', email: 'eu@ex.pt', name: 'Eu');
const token = 'AbCdEfGhIjKlMnOpQrStUv';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Translations.load(const Locale('pt'));
  });

  test('a mensagem partilhada leva o link /b/', () {
    expect(BirthdayRequestLinks.shareMessage(token), allOf(contains('Deixa aqui o teu'), endsWith('/b/$token')));
  });

  Future<void> pump(WidgetTester tester, {required ApiClient? api}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(me),
          apiClientProvider.overrideWithValue(api),
          chatEventsProvider.overrideWithValue(const Stream.empty()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: Padding(padding: EdgeInsets.all(20), child: BirthdayRequestCard())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mostra quantas pessoas já deixaram a data, sem erros de layout', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'velas.api.refreshToken': 'r1'});
    final api = ApiClient(
      'https://api.test',
      client: MockClient((req) async {
        final body = req.url.path == '/auth/refresh'
            ? {'access_token': 'a', 'refresh_token': 'r2', 'user': {'id': 'me'}}
            : {'token': token, 'answers': 3};
        return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
      }),
    );
    await api.restore();
    await pump(tester, api: api);
    expect(tester.takeException(), isNull);
    expect(find.text('Não sabes a data? Pede-a'), findsOneWidget);
    expect(find.text('3 pessoas já deixaram a data pelo teu link.'), findsOneWidget);
    expect(find.text('Partilhar'), findsOneWidget);
  });

  testWidgets('sem servidor (modo local) não aparece', (tester) async {
    await pump(tester, api: null);
    expect(find.text('Não sabes a data? Pede-a'), findsNothing);
  });
}
