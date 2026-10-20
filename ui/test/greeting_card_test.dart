import 'package:aniversarios/core/chat_providers.dart';
import 'package:aniversarios/core/i18n/translations.dart';
import 'package:aniversarios/core/providers.dart';
import 'package:aniversarios/core/theme/app_colors.dart';
import 'package:aniversarios/data/models/card_models.dart';
import 'package:aniversarios/data/models/chat_models.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/data/repositories/cards_repository.dart';
import 'package:aniversarios/data/repositories/chat_repository.dart';
import 'package:aniversarios/features/cards/card_links.dart';
import 'package:aniversarios/features/cards/card_screen.dart';
import 'package:aniversarios/features/cards/wall_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

const token = 'AbCdEfGhIjKlMnOpQrStUv';
const tomas = UserProfile(id: 'tomas', email: 'tomas@ex.pt', name: 'Tomás');
const rita = UserProfile(id: 'rita', email: 'rita@ex.pt', name: 'Rita Lopes');

class FakeCards implements CardsRepository {
  final opened = <String>[];
  final claimed = <String>[];
  var wallSeen = 0;
  List<ReceivedCard> wall = [
    ReceivedCard(
      id: 'w2',
      sender: const ChatUser(userId: 'rita', name: 'Rita Lopes'),
      body: 'Mais um abraço!',
      receivedAt: DateTime(2026, 5, 3),
      seen: false,
    ),
    ReceivedCard(
      id: 'w1',
      sender: const ChatUser(userId: 'gil', name: 'Gil Costa'),
      body: 'Parabéns, Tomás!',
      receivedAt: DateTime(2025, 5, 3),
    ),
  ];

  @override
  Future<List<ReceivedCard>> received() async => wall;

  @override
  Future<void> markWallSeen() async => wallSeen++;

  @override
  Future<GreetingCard> preview(String t) async => GreetingCard(
    token: t,
    senderId: 'rita',
    senderName: 'Rita Lopes',
    recipientName: 'Tomás',
    body: 'Que seja um ano incrível!',
    createdAt: DateTime(2026, 5, 3),
  );

  @override
  Future<void> markOpened(String t) async => opened.add(t);

  @override
  Future<ClaimedCard> claim(String t) async {
    claimed.add(t);
    return const ClaimedCard(senderId: 'rita', conversationId: 'c-rita');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

class FakeChat implements ChatRepository {
  @override
  Future<List<Conversation>> fetchConversations() async => const [];

  @override
  Future<Conversation> openDirect(String userId) async => Conversation(
    id: 'c-$userId',
    isGroup: false,
    title: 'Rita Lopes',
    otherUser: ChatUser(userId: userId, name: 'Rita Lopes'),
    createdAt: DateTime(2026),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('pt_PT');
    await Translations.load(const Locale('pt'));
  });

  group('links', () {
    test('reconhece o link da app, o da página e o referrer da Play Store', () {
      expect(CardLinks.tokenFrom(Uri.parse('com.eupasoft.velas://app/card/$token')), token);
      expect(CardLinks.tokenFrom(Uri.parse('https://birthday.ly/c/$token')), token);
      expect(CardLinks.tokenFrom(Uri.parse('https://birthday.ly/g/K7P2QX9M')), isNull);
      expect(CardLinks.tokenFrom(Uri.parse('https://birthday.ly/c/curto')), isNull);
      expect(CardLinks.tokenFromText('  https://birthday.ly/c/$token\n'), token);
      expect(CardLinks.tokenFromText('uma lista de compras'), isNull);
      expect(CardLinks.tokenFromReferrer('card=$token'), token);
      expect(CardLinks.tokenFromReferrer('utm_source=google-play&utm_medium=organic'), isNull);
    });

    test('a mensagem partilhada leva o link e não revela o texto', () {
      expect(CardLinks.shareMessage('Tomás', token), allOf(startsWith('Parabéns, Tomás! 🎂'), endsWith('/c/$token')));
    });
  });

  Future<FakeCards> open(WidgetTester tester, UserProfile? user, {String at = '/card/$token'}) async {
    final cards = FakeCards();
    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(path: '/wall', builder: (_, _) => const WallScreen()),
        GoRoute(path: '/banner', builder: (_, _) => const Scaffold(body: WallBanner())),
        GoRoute(path: '/card/:token', builder: (_, s) => CardScreen(token: s.pathParameters['token']!)),
        GoRoute(path: '/register', builder: (_, _) => const Scaffold(body: Text('registo'))),
        GoRoute(path: '/login', builder: (_, _) => const Scaffold(body: Text('login'))),
        GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('início'))),
        GoRoute(path: '/chats/:id', builder: (_, s) => Scaffold(body: Text('conversa ${s.pathParameters['id']}'))),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(user),
          cardsRepositoryProvider.overrideWithValue(cards),
          chatRepositoryProvider.overrideWithValue(FakeChat()),
          chatEventsProvider.overrideWithValue(const Stream.empty()),
        ],
        child: MaterialApp.router(theme: ThemeData(extensions: const [AppPalette.light]), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return cards;
  }

  testWidgets('sem conta lê a mensagem e vai criar conta para responder', (tester) async {
    final cards = await open(tester, null);
    expect(find.text('Parabéns, Tomás! 🎉'), findsOneWidget);
    expect(find.text('Que seja um ano incrível!'), findsOneWidget);
    expect(cards.opened, [token]);

    await tester.tap(find.text('Responder a Rita'));
    await tester.pumpAndSettle();
    expect(find.text('registo'), findsOneWidget);
  });

  testWidgets('com conta guarda o cartão e abre a conversa com quem o enviou', (tester) async {
    final cards = await open(tester, tomas);
    await tester.tap(find.text('Responder a Rita'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(cards.claimed, [token]);
    expect(find.text('conversa c-rita'), findsOneWidget);
  });

  testWidgets('o mural mostra os parabéns por ano, destaca os novos e marca-os como vistos', (tester) async {
    final cards = await open(tester, tomas, at: '/wall');
    expect(find.text('2 mensagens de parabéns de 2 pessoas'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('Mais um abraço!'), findsOneWidget);
    expect(find.text('Nova'), findsOneWidget);
    expect(cards.wallSeen, 1);

    await tester.tap(find.text('Agradecer a Rita'));
    await tester.pumpAndSettle();
    expect(find.text('conversa c-rita'), findsOneWidget);
  });

  testWidgets('o Início avisa quando chegam parabéns novos ao mural', (tester) async {
    await open(tester, tomas, at: '/banner');
    expect(find.text('Rita deixou-te uma mensagem de parabéns 🎉'), findsOneWidget);
    await tester.tap(find.text('Abre o teu mural para as leres'));
    await tester.pumpAndSettle();
    expect(find.text('O teu mural'), findsOneWidget);
  });

  testWidgets('quem enviou vê o próprio cartão sem o marcar como aberto', (tester) async {
    final cards = await open(tester, rita);
    expect(find.text('Este é o cartão que enviaste.'), findsOneWidget);
    expect(find.text('Responder a Rita'), findsNothing);
    expect(cards.opened, isEmpty);
  });
}
