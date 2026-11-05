// Letra grande (acessibilidade): percorre os ecrãs num telemóvel pequeno com
// o texto a 130%, 150% (o máximo da app) e 200% (o máximo do Android) e falha
// se algum transbordar ("overflowed"), com as letras verdadeiras da app.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aniversarios/app.dart';
import 'package:aniversarios/core/chat_providers.dart';
import 'package:aniversarios/core/i18n/translations.dart';
import 'package:aniversarios/core/providers.dart';
import 'package:aniversarios/core/router/app_router.dart';
import 'package:aniversarios/data/api/api_client.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/data/repositories/auth_repository.dart';
import 'package:aniversarios/services/home_widget_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const me = UserProfile(id: 'me', email: 'eu@ex.pt', name: 'Margarida Albuquerque', username: 'margarida.albuquerque');

/// Com servidor, já aceitou os termos (senão o ecrã dos termos fica por cima de tudo).
const meOnline = UserProfile(
  id: 'me',
  email: 'eu@ex.pt',
  name: 'Margarida Albuquerque',
  username: 'margarida.albuquerque',
  termsVersion: 'x',
);

class FakeAuth implements AuthRepository {
  FakeAuth(this.current);

  @override
  UserProfile? current;

  @override
  bool get isLocal => true;

  @override
  bool get supportsGoogle => false;

  @override
  Stream<UserProfile?> get changes => Stream.value(current);

  @override
  Stream<void> get passwordRecovery => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

/// As letras da app (Plus Jakarta Sans e Fraunces, em test/fonts, as mesmas
/// que o google_fonts descarrega) com o nome que o tema pede para cada peso.
Future<void> loadFonts() async {
  final families = <String, String>{};
  for (final w in FontWeight.values) {
    final file = w.value.clamp(400, 800);
    families[GoogleFonts.plusJakartaSans(fontWeight: w).fontFamily!] = 'test/fonts/PlusJakartaSans-$file.ttf';
    families[GoogleFonts.fraunces(fontWeight: w).fontFamily!] = 'test/fonts/Fraunces-$file.ttf';
  }
  for (final MapEntry(key: family, value: path) in families.entries) {
    final bytes = File(path).readAsBytes().then(ByteData.sublistView);
    await (FontLoader(family)..addFont(bytes)).load();
  }
}

final now = DateTime.now();
Person person(String id, String name, int inDays, {int? year, String? category, String notes = ''}) {
  final d = now.add(Duration(days: inDays));
  return Person(
    id: id,
    name: name,
    day: d.day,
    month: d.month,
    year: year,
    categoryId: category,
    notes: notes,
    relation: 'Melhor amiga de infância',
    createdAt: DateTime(2026),
  );
}

final data = AppData(
  loaded: true,
  categories: const [
    PersonCategory(id: 'c1', name: 'Família', color: 0),
    PersonCategory(id: 'c2', name: 'Amigos de longa data', color: 1),
    PersonCategory(id: 'c3', name: 'Trabalho', color: 2),
  ],
  people: [
    person('p1', 'Maria Constança Vasconcelos', 0, year: 1990, category: 'c1', notes: 'Gosta de livros e de plantas.'),
    person('p2', 'Bartolomeu Figueiredo', 1, year: 1985, category: 'c2'),
    person('p3', 'Ana', 5, category: 'c3'),
    person('p4', 'Guilherme Albuquerque Sampaio', 12, year: 2001),
    person('p5', 'Rita', 40),
  ],
  gifts: [
    GiftIdea(id: 'g1', personId: 'p1', title: 'Livro de receitas tradicionais portuguesas', price: 24.9, createdAt: DateTime(2026)),
    GiftIdea(id: 'g2', personId: 'p2', title: 'Bilhetes para o concerto', price: 120, createdAt: DateTime(2026)),
  ],
  messages: [
    BirthdayMessage(
      id: 'm1',
      personId: 'p1',
      body: 'Parabéns, Maria! Que este ano te traga tudo de bom.',
      updatedAt: DateTime(2026),
      scheduledAt: now.add(const Duration(days: 1)),
      scheduleVia: ScheduleVia.remind,
    ),
  ],
);

const loggedInRoutes = [
  '/home',
  '/agenda',
  '/people',
  '/gifts',
  '/person/p1',
  '/person/p1/message',
  '/person/new',
  '/person/p1/edit',
  '/profile',
  '/profile/payments',
  '/profile/plans',
  '/profile/help',
  '/profile/accessibility',
  '/profile/categories',
  '/people/import?from=calendar',
  '/groups/new?personId=p1',
];

const loggedOutRoutes = ['/welcome', '/login', '/register', '/forgot-password'];

/// Com servidor: conversas, amigos, mural, grupos e o resto que só existe online.
const serverRoutes = [
  '/home',
  '/people',
  '/gifts',
  '/person/p1',
  '/person/p1/message',
  '/chats/c1',
  '/chats/c1/info',
  '/chats/c2',
  '/chats/c2/info',
  '/friends',
  '/wall',
  '/chat-settings',
  '/chat-settings/blocked',
  '/groups/g1',
  '/profile',
  '/profile/help',
  '/people/requests',
];

final _iso = DateTime.now().subtract(const Duration(hours: 3)).toUtc().toIso8601String();
Map<String, Object?> _user(String id, String name) => {
  'user_id': id,
  'display_name': name,
  'username': name.toLowerCase().replaceAll(' ', '.'),
  'photo_url': null,
  'online': id == 'u1',
  'last_seen_at': _iso,
};
Map<String, Object?> _msg(String id, String conv, String? sender, String name, String body) => {
  'id': id,
  'conversation_id': conv,
  'sender_id': sender,
  'sender_name': name,
  'sender_photo_url': null,
  'kind': 'text',
  'body': body,
  'media_url': null,
  'reactions': [
    {'emoji': '🎉', 'user_id': 'u1'},
  ],
  'reply': null,
  'created_at': _iso,
  'deleted': false,
};
const _long = 'Bartolomeu Figueiredo de Vasconcelos';
final _conversations = [
  {
    'id': 'c1',
    'kind': 'direct',
    'title': _long,
    'other_user': _user('u1', _long),
    'last_message': _msg('m1', 'c1', 'u1', _long, 'Parabéns atrasados! Vens jantar connosco no sábado à noite?'),
    'last_message_at': _iso,
    'unread_count': 12,
    'muted_until': '9999-12-31T00:00:00Z',
    'pinned': true,
    'created_at': _iso,
    'participants': [
      {..._user('me', me.name), 'last_read_at': _iso},
      {..._user('u1', _long), 'last_read_at': _iso},
    ],
  },
  {
    'id': 'c2',
    'kind': 'group',
    'group_id': 'g1',
    'title': 'Prenda de anos da Maria Constança',
    'celebrant_name': 'Maria Constança Vasconcelos',
    'last_message': _msg('m2', 'c2', 'u2', 'Guilherme Albuquerque', 'Já encomendei o livro, falta pagar a parte da Rita'),
    'last_message_at': _iso,
    'unread_count': 3,
    'created_at': _iso,
    'participants': [
      {..._user('me', me.name), 'last_read_at': _iso},
      {..._user('u1', _long), 'last_read_at': _iso},
      {..._user('u2', 'Guilherme Albuquerque Sampaio'), 'last_read_at': _iso},
    ],
  },
];
Map<String, Object?> _member(String id, String? user, String name, {bool paid = false}) => {
  'id': id,
  'group_id': 'g1',
  'user_id': user,
  'display_name': name,
  'username': user == null ? null : name.toLowerCase().replaceAll(' ', '.'),
  'custom_amount': null,
  'payment_methods': {},
  'paid_at': paid ? _iso : null,
  'paid_method': paid ? 'mbway' : null,
  'confirmed_at': null,
  'created_at': _iso,
};
final _group = {
  'id': 'g1',
  'created_by': 'me',
  'title': 'Prenda de anos da Maria Constança',
  'celebrant_name': 'Maria Constança Vasconcelos',
  'celebrant_day': now.day,
  'celebrant_month': now.month,
  'person_id': 'p1',
  'gift_description': 'Livro de receitas tradicionais portuguesas e uma planta grande para a varanda',
  'gift_link': 'https://www.exemplo.pt/livros/receitas-tradicionais-portuguesas',
  'target_amount': 120.5,
  'split_mode': 'equal',
  'buyer_member_id': 'gm2',
  'deadline': now.add(const Duration(days: 3)).toIso8601String().substring(0, 10),
  'purchased_at': null,
  'invite_code': 'K7P2QX9M',
  'photo_url': null,
  'created_at': _iso,
  'group_members': [
    _member('gm1', 'me', me.name),
    _member('gm2', 'u1', _long, paid: true),
    _member('gm3', null, 'Tia Rosa Maria das Dores'),
  ],
  'group_invitations': [],
};

/// Janelas que só abrem com um toque: em cada ecrã, os botões a tocar (cada
/// janela fecha-se com "voltar" antes da seguinte).
const localSheets = {
  '/person/new': ['Escolher data'],
  '/person/p1/message': ['Agendar'],
};
const serverSheets = {
  // Com servidor, "Enviar" pergunta como (cartão, mural ou texto).
  '/person/p1/message': ['Agendar', 'Enviar'],
  '/groups/g1': ['Pagar a '],
};

/// Respostas do servidor para cada pedido (o resto: 404, os ecrãs mostram o erro).
Object? _serve(String method, String path) => switch (path) {
  '/friends' => {
    'friends': [_user('u1', _long), _user('u2', 'Guilherme Albuquerque Sampaio')],
    'incoming': [
      {'id': 'r1', ..._user('u3', 'Constança Maria de Albuquerque e Castro'), 'created_at': _iso},
    ],
    'outgoing': [],
  },
  '/conversations' => _conversations,
  '/conversations/c1' => _conversations[0],
  '/conversations/c2' => _conversations[1],
  '/conversations/c1/messages' || '/conversations/c2/messages' => {
    'messages': [
      _msg('x1', path.split('/')[2], 'u1', _long, 'Olá! Já viste a ideia para a prenda? Acho que ela ia adorar, mas é um bocadinho cara.'),
      _msg('x2', path.split('/')[2], 'me', me.name, 'Sim, gosto muito! Podemos dividir por todos.'),
    ],
    'has_more': false,
  },
  '/groups' => [_group],
  '/groups/g1/payee' => {'mbway_phone': '912345678', 'revolut_tag': 'bartolomeu', 'accepts_cash': true},
  '/invitations' => [],
  '/blocks' => [
    {..._user('u4', 'Utilizador com um nome mesmo muito comprido'), 'blocked_at': _iso},
  ],
  '/cards/received' => [
    {
      'id': 'k1',
      'body': 'Muitos parabéns! Que este ano seja incrível e cheio de aventuras.',
      'via': 'wall',
      'created_at': _iso,
      'received_at': _iso,
      'seen': false,
      'sender': _user('u1', _long),
    },
  ],
  '/cards/sent' => [
    {
      'id': 'k2',
      'token': 'AbCdEfGhIjKlMnOpQrStUv',
      'person_id': 'p1',
      'recipient_name': 'Maria',
      'body': 'Parabéns, Maria!',
      'via': 'link',
      'created_at': _iso,
      'opened_at': _iso,
      'claimed_at': null,
    },
  ],
  '/birthday-request' => {'token': 'abcdefghijklmnop', 'answers': 4, 'pending': 2, 'enabled': true, 'open': true},
  '/birthday-request/answers' => [
    {'id': 'a1', 'name': 'Constança Maria de Albuquerque e Castro', 'day': 3, 'month': 5, 'year': 1990},
    {'id': 'a2', 'name': 'Zé', 'day': 12, 'month': 12, 'year': null},
  ],
  '/legal/info' => {'terms_version': 'x', 'support_email': 'apoio@birthdayly.pt'},
  '/stickers' => [],
  _ => null,
};

Future<ApiClient> fakeServer() async {
  FlutterSecureStorage.setMockInitialValues({'velas.api.refreshToken': 'r1'});
  final api = ApiClient(
    'https://api.test',
    client: MockClient((req) async {
      if (req.url.path == '/auth/refresh') {
        return http.Response(jsonEncode({'access_token': 'a', 'refresh_token': 'r2', 'user': {'id': 'me'}}), 200);
      }
      final body = _serve(req.method, req.url.path);
      if (body == null) return http.Response(jsonEncode({'error': 'not_found'}), 404);
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }),
  );
  await api.restore();
  return api;
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting();
    await Translations.load(const Locale('pt'));
    await loadFonts();
    // Links de convite/cartões (app_links): sem plugin nativo nos testes.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('com.llfbandit.app_links/events'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
  });

  Future<List<String>> visit(
    WidgetTester tester,
    UserProfile? user,
    List<String> routes,
    double scale, {
    double height = 780,
    ApiClient? api,
  }) async {
    // O rootBundle guarda os ficheiros já pedidos (com o relógio do teste anterior).
    rootBundle.clear();
    tester.view.physicalSize = Size(360, height) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'velas.a11y.textScale': scale,
      'velas.onboarded.me': true,
    });
    final prefs = await SharedPreferences.getInstance();

    final problems = <String>[];
    var route = '';
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.toString();
      if (!text.contains('overflowed')) return original?.call(details);
      final where = RegExp(r'file://[^\s]*?/lib/([^\s:]+:\d+)').allMatches(text).map((m) => m.group(1)).toSet();
      final by = RegExp(r'overflowed by ([\d.]+) pixels on the (\w+)').firstMatch(text);
      problems.add('$route${height > 780 ? ' (alto)' : ''} → ${by?.group(1)}px (${by?.group(2)}) ${where.join(', ')}');
    };

    final noop = Provider<void>((_) {});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          authRepositoryProvider.overrideWithValue(FakeAuth(user)),
          apiClientProvider.overrideWithValue(api),
          chatSocketProvider.overrideWithValue(null),
          chatEventsProvider.overrideWithValue(const Stream.empty()),
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
    final container = ProviderScope.containerOf(tester.element(find.byType(VelasApp)));
    for (final r in routes) {
      route = r;
      container.read(routerProvider).go(r);
      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          // As traduções e as imagens carregam-se de verdade (fora do relógio falso dos testes).
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pump(const Duration(milliseconds: 300));
        }
      }

      await settle();
      final sheets = api == null ? localSheets : serverSheets;
      for (final label in sheets[r.split('?').first] ?? const <String>[]) {
        final button = label.endsWith(' ') ? find.textContaining(label) : find.text(label);
        // Nas listas, o botão só existe depois de deslizar até ele (a partir do topo).
        if (button.evaluate().isEmpty) {
          await tester.drag(find.byType(Scrollable).first, const Offset(0, 20000), warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 300));
        }
        for (var i = 0; i < 15 && button.evaluate().isEmpty; i++) {
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -300), warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 200));
        }
        if (button.evaluate().isEmpty) {
          problems.add('$r${height > 780 ? ' (alto)' : ''} → botão "$label" não encontrado');
          continue;
        }
        route = '$r [$label]';
        await tester.ensureVisible(button.first);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(button.first, warnIfMissed: false);
        await settle();
        final opened = find.byType(BottomSheet).evaluate().isNotEmpty || find.byType(Dialog).evaluate().isNotEmpty;
        if (!opened) {
          problems.add('$r → "$label" não abriu nenhuma janela');
          continue;
        }
        await tester.binding.handlePopRoute();
        await settle();
      }
    }
    FlutterError.onError = original;
    return problems;
  }

  for (final scale in [1.3, 1.5, 2.0]) {
    testWidgets('com sessão, texto a ${(scale * 100).round()}%: nada transborda', (tester) async {
      // Num ecrã alto, as listas desenham tudo (num normal, só o que cabe).
      final problems = [
        ...await visit(tester, me, loggedInRoutes, scale),
        ...await visit(tester, me, loggedInRoutes, scale, height: 4000),
      ];
      debugPrint(problems.join('\n'));
      expect(problems, isEmpty);
    });

    testWidgets('com servidor, texto a ${(scale * 100).round()}%: nada transborda', (tester) async {
      final api = await fakeServer();
      final problems = [
        ...await visit(tester, meOnline, serverRoutes, scale, api: api),
        ...await visit(tester, meOnline, serverRoutes, scale, height: 4000, api: api),
        // O ecrã "Antes de continuares" (termos por aceitar).
        ...await visit(tester, me, ['/home'], scale, api: api),
      ];
      debugPrint(problems.join('\n'));
      expect(problems, isEmpty);
    });

    testWidgets('sem sessão, texto a ${(scale * 100).round()}%: nada transborda', (tester) async {
      final problems = [
        ...await visit(tester, null, loggedOutRoutes, scale),
        ...await visit(tester, null, loggedOutRoutes, scale, height: 4000),
      ];
      debugPrint(problems.join('\n'));
      expect(problems, isEmpty);
    });
  }
}
