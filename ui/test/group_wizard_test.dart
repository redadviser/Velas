// O assistente "Prenda em grupo": três passos, validação antes de avançar e
// "voltar" que recua um passo. Com o texto a 200% para apanhar transbordos.
import 'package:aniversarios/app.dart';
import 'package:aniversarios/core/chat_providers.dart';
import 'package:aniversarios/core/i18n/translations.dart';
import 'package:aniversarios/core/providers.dart';
import 'package:aniversarios/core/router/app_router.dart';
import 'package:aniversarios/core/utils/birthday_utils.dart';
import 'package:aniversarios/services/home_widget_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'large_text_test.dart' show FakeAuth, data, loadFonts, me;

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting();
    await Translations.load(const Locale('pt'));
    await loadFonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('com.llfbandit.app_links/events'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
  });

  Future<void> open(WidgetTester tester, String route) async {
    rootBundle.clear();
    tester.view.physicalSize = const Size(360, 780) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'velas.onboarded.me': true,
      'velas.a11y.textScale': 2.0,
      'velas.locale': 'pt', // o ambiente de teste é en_US
    });
    final prefs = await SharedPreferences.getInstance();
    final noop = Provider<void>((_) {});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          authRepositoryProvider.overrideWithValue(FakeAuth(me)),
          apiClientProvider.overrideWithValue(null),
          chatSocketProvider.overrideWithValue(null),
          chatEventsProvider.overrideWith((_) => const Stream.empty()),
          appDataProvider.overrideWith((_) => Stream.value(data)),
          notificationSyncProvider.overrideWith((ref) => ref.watch(noop)),
          chatNotificationsProvider.overrideWith((ref) => ref.watch(noop)),
          pushRegistrationProvider.overrideWith((ref) => ref.watch(noop)),
          dataSyncProvider.overrideWith((ref) => ref.watch(noop)),
          homeWidgetSyncProvider.overrideWith((ref) => ref.watch(noop)),
        ],
        child: const VelasApp(),
      ),
    );
    ProviderScope.containerOf(tester.element(find.byType(VelasApp))).read(routerProvider).go(route);
    await settle(tester);
  }

  testWidgets('avança pelos três passos e volta atrás', (tester) async {
    await open(tester, '/groups/new?personId=p1');
    // p1 faz anos hoje: o prazo não pode ficar no passado.
    final deadline = find.descendant(of: find.byType(OutlinedButton), matching: find.byType(Text));
    expect(tester.widget<Text>(deadline).data, Fmt.dayMonth(BirthdayUtils.today()));

    await tester.tap(find.text('Continuar'));
    await settle(tester);
    expect(find.text('Como querem dividir?'), findsOneWidget);

    await tester.tap(find.text('Continuar'));
    await settle(tester);
    expect(find.textContaining('É segredo'), findsOneWidget);
    expect(find.text('Criar grupo'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Como querem dividir?'), findsOneWidget);
  });

  testWidgets('sem para quem nem valor, não avança', (tester) async {
    await open(tester, '/groups/new');
    await tester.tap(find.text('Continuar'));
    await settle(tester);
    expect(find.text('Indica para quem é a prenda.'), findsOneWidget);
    expect(find.text('Como querem dividir?'), findsNothing);
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}
