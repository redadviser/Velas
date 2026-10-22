import 'dart:convert';

import 'package:aniversarios/core/i18n/translations.dart';
import 'package:aniversarios/core/providers.dart';
import 'package:aniversarios/core/theme/app_colors.dart';
import 'package:aniversarios/core/theme/app_theme.dart';
import 'package:aniversarios/data/api/api_auth_repository.dart';
import 'package:aniversarios/data/api/api_client.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/data/repositories/auth_repository.dart';
import 'package:aniversarios/features/profile/accessibility_screen.dart';
import 'package:aniversarios/features/profile/legal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const version = '2026-10-22';
const LegalInfo info = (termsVersion: version, supportEmail: null, privacyUrl: 'p', termsUrl: 't');

class FakeAuth implements AuthRepository {
  var accepted = 0;
  var signedOut = 0;

  @override
  Future<void> acceptTerms() async => accepted++;

  @override
  Future<void> signOut() async => signedOut++;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Translations.load(const Locale('pt'));
  });

  Future<void> pumpGate(WidgetTester tester, UserProfile user, FakeAuth auth) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(user),
          legalInfoProvider.overrideWith((_) async => info),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TermsGate(child: Scaffold(body: Text('app'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('quem ainda não aceitou os termos confirma a idade e aceita', (tester) async {
    final auth = FakeAuth();
    await pumpGate(tester, const UserProfile(id: 'me', email: 'eu@ex.pt', name: 'Eu'), auth);
    expect(find.text('Antes de continuares'), findsOneWidget);
    // Sem a caixa marcada não se aceita.
    await tester.tap(find.text('Aceitar e continuar'));
    await tester.pumpAndSettle();
    expect(auth.accepted, 0);

    await tester.tap(find.textContaining('Tenho 16 anos ou mais'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceitar e continuar'));
    await tester.pumpAndSettle();
    expect(auth.accepted, 1);

    await tester.tap(find.text('Agora não (terminar sessão)'));
    await tester.pumpAndSettle();
    expect(auth.signedOut, 1);
  });

  testWidgets('uma versão antiga pede outra vez; a atual deixa passar', (tester) async {
    await pumpGate(
      tester,
      const UserProfile(id: 'me', email: 'eu@ex.pt', name: 'Eu', termsVersion: '2025-01-01'),
      FakeAuth(),
    );
    expect(find.text('Atualizámos os nossos termos'), findsOneWidget);

    await pumpGate(
      tester,
      const UserProfile(id: 'me', email: 'eu@ex.pt', name: 'Eu', termsVersion: version),
      FakeAuth(),
    );
    expect(find.text('Atualizámos os nossos termos'), findsNothing);
    expect(find.text('Antes de continuares'), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  test('criar conta e aceitar os termos ficam registados no servidor', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final sent = <String, Object?>{};
    Map<String, Object?> user(String? terms) => {
      'id': 'me',
      'email': 'eu@ex.pt',
      'display_name': 'Eu',
      'terms_version': terms,
    };
    final api = ApiClient(
      'https://api.test',
      client: MockClient((req) async {
        sent[req.url.path] = req.body.isEmpty ? null : jsonDecode(req.body);
        final body = req.url.path == '/me/accept-terms'
            ? user(version)
            : {'access_token': 'a', 'refresh_token': 'r', 'user': user(null)};
        return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
      }),
    );
    final repo = ApiAuthRepository(api, await SharedPreferences.getInstance());

    await repo.signUp(name: 'Eu', username: 'eu_mesmo', email: 'eu@ex.pt', password: 'segredo123');
    expect((sent['/auth/signup'] as Map)['accept_terms'], isTrue);

    await repo.acceptTerms();
    expect(sent.containsKey('/me/accept-terms'), isTrue);
    expect(repo.current?.termsVersion, version);
  });

  test('o contraste alto escurece o texto secundário e os contornos', () {
    final normal = AppTheme.light().extension<AppPalette>()!;
    final strong = AppTheme.light(highContrast: true).extension<AppPalette>()!;
    expect(strong.mutedForeground, isNot(normal.mutedForeground));
    expect(strong.border, isNot(normal.border));
    expect(strong.mutedForeground.computeLuminance(), lessThan(normal.mutedForeground.computeLuminance()));
  });

  testWidgets('as definições de acessibilidade ficam guardadas no telemóvel', (tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: const AccessibilityScreen()),
      ),
    );
    expect(find.text('Do telemóvel'), findsOneWidget);

    await tester.tap(find.text('Contraste alto'));
    await tester.tap(find.text('Reduzir animações'));
    container.read(accessibilityProvider.notifier).setTextScale(1.3);
    await tester.pumpAndSettle();
    expect(find.text('130%'), findsOneWidget);
    expect(prefs.getBool('velas.a11y.highContrast'), isTrue);
    expect(prefs.getBool('velas.a11y.reduceMotion'), isTrue);
    expect(prefs.getDouble('velas.a11y.textScale'), 1.3);

    // Voltar ao tamanho do telemóvel esquece a escolha.
    container.read(accessibilityProvider.notifier).setTextScale(null);
    expect(prefs.getDouble('velas.a11y.textScale'), isNull);
  });
}
