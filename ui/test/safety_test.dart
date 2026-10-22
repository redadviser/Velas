import 'dart:convert';

import 'package:aniversarios/core/chat_providers.dart';
import 'package:aniversarios/core/i18n/translations.dart';
import 'package:aniversarios/core/providers.dart';
import 'package:aniversarios/core/theme/app_theme.dart';
import 'package:aniversarios/data/api/api_client.dart';
import 'package:aniversarios/data/models/chat_models.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/features/chat/safety.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const me = UserProfile(id: 'me', email: 'eu@ex.pt', name: 'Eu');
const quim = ChatUser(userId: 'quim', name: 'Quim Silva', username: 'quim');

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Translations.load(const Locale('pt'));
  });

  /// API falsa: guarda os pedidos (método, caminho, corpo) e responde a GET /blocks com [blocked].
  Future<(ApiClient, List<(String, Object?)>)> fakeApi({List<Map<String, Object?>> blocked = const []}) async {
    FlutterSecureStorage.setMockInitialValues({'velas.api.refreshToken': 'r1'});
    final calls = <(String, Object?)>[];
    final api = ApiClient(
      'https://api.test',
      client: MockClient((req) async {
        if (req.url.path == '/auth/refresh') {
          return http.Response(jsonEncode({'access_token': 'a', 'refresh_token': 'r2', 'user': {'id': 'me'}}), 200);
        }
        calls.add(('${req.method} ${req.url.path}', req.body.isEmpty ? null : jsonDecode(req.body)));
        if (req.url.path == '/blocks') return http.Response(jsonEncode(blocked), 200, headers: {'content-type': 'application/json'});
        return http.Response('', 204);
      }),
    );
    await api.restore();
    return (api, calls);
  }

  Future<void> pump(WidgetTester tester, ApiClient api, Widget Function(BuildContext, WidgetRef) build) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(me),
          apiClientProvider.overrideWithValue(api),
          chatEventsProvider.overrideWithValue(const Stream.empty()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: Consumer(builder: (context, ref, _) => Center(child: build(context, ref)))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('denunciar uma mensagem envia o motivo, a mensagem e o bloqueio', (tester) async {
    final (api, calls) = await fakeApi();
    await pump(
      tester,
      api,
      (context, ref) => TextButton(onPressed: () => showReportSheet(context, ref, quim, messageId: 'm1'), child: const Text('abrir')),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Denunciar mensagem'), findsOneWidget);
    // Sem motivo não se envia.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Enviar denúncia')).onPressed, isNull);
    await tester.tap(find.text('Spam ou publicidade'));
    await tester.enterText(find.byType(TextField), 'Publicidade no grupo');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar denúncia'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(calls.first.$1, 'POST /users/quim/report');
    expect(calls.first.$2, {'reason': 'spam', 'details': 'Publicidade no grupo', 'message_id': 'm1', 'block': true});
    expect(find.textContaining('vai analisar a denúncia'), findsOneWidget);
  });

  testWidgets('bloquear pede confirmação e chama o servidor', (tester) async {
    final (api, calls) = await fakeApi();
    await pump(tester, api, (context, ref) => TextButton(onPressed: () => confirmBlock(context, ref, quim), child: const Text('abrir')));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Bloquear Quim?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Bloquear'));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.$1), contains('POST /users/quim/block'));
    expect(find.text('Bloqueaste Quim.'), findsOneWidget);
  });

  testWidgets('a lista dos bloqueados deixa desbloquear', (tester) async {
    final (api, calls) = await fakeApi(blocked: [
      {'user_id': 'quim', 'display_name': 'Quim Silva', 'username': 'quim', 'photo_url': null},
    ]);
    await pump(tester, api, (_, _) => const SizedBox(width: 500, height: 800, child: BlockedUsersScreen()));
    expect(find.text('Quim Silva'), findsOneWidget);
    await tester.tap(find.text('Desbloquear'));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.$1), contains('DELETE /users/quim/block'));
    expect(find.text('Ninguém bloqueado'), findsOneWidget);
  });
}
