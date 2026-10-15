import 'dart:async';

import 'package:aniversarios/core/chat_providers.dart';
import 'package:aniversarios/core/i18n/translations.dart';
import 'package:aniversarios/core/providers.dart';
import 'package:aniversarios/core/theme/app_colors.dart';
import 'package:aniversarios/data/api/chat_socket.dart';
import 'package:aniversarios/data/models/chat_models.dart';
import 'package:aniversarios/data/models/group_models.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/data/repositories/chat_repository.dart';
import 'package:aniversarios/features/chat/conversation_info_screen.dart';
import 'package:aniversarios/features/chat/conversations_list.dart';
import 'package:aniversarios/features/home/home_inbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

const me = UserProfile(id: 'me', email: 'eu@ex.pt', name: 'Eu');

Conversation conv(
  String id, {
  bool group = false,
  int unread = 0,
  int hour = 10,
  bool pinned = false,
  DateTime? mutedUntil,
  String title = '',
}) => Conversation(
  id: id,
  isGroup: group,
  title: title.isEmpty ? id : title,
  unreadCount: unread,
  pinned: pinned,
  mutedUntil: mutedUntil,
  lastMessageAt: DateTime(2026, 10, 15, hour),
  lastMessage: LastMessage(
    id: 'last-$id',
    senderId: 'gil',
    senderName: 'Gil Costa',
    kind: MessageKind.text,
    body: 'Olá de $id',
    createdAt: DateTime(2026, 10, 15, hour),
  ),
  createdAt: DateTime(2026),
);

ChatMessage incoming(String conversationId, {String sender = 'gil', String body = 'Já compraste?'}) => ChatMessage(
  id: 'm-$conversationId-$body',
  conversationId: conversationId,
  senderId: sender,
  senderName: 'Gil Costa',
  body: body,
  createdAt: DateTime(2026, 10, 15, 12),
);

class FakeChat implements ChatRepository {
  FakeChat(this.conversations);

  List<Conversation> conversations;
  final prefs = <(String, DateTime?, bool?)>[];

  @override
  Future<List<Conversation>> fetchConversations() async => conversations;

  @override
  Future<FriendsList> fetchFriends() async => FriendsList.empty;

  @override
  Future<Conversation> fetchConversation(String id) async => conversations.firstWhere((c) => c.id == id);

  @override
  Future<MessagePage> fetchMessages(String id, {String? before, int limit = 50}) async =>
      const MessagePage(messages: [], hasMore: false);

  @override
  Future<Conversation> setPrefs(String id, {DateTime? Function()? mutedUntil, bool? pinned}) async {
    final c = conversations.firstWhere((c) => c.id == id);
    prefs.add((id, mutedUntil?.call(), pinned));
    final updated = c.copyWith(mutedUntil: mutedUntil, pinned: pinned);
    conversations = [for (final x in conversations) x.id == id ? updated : x];
    return updated;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting();
    await Translations.load(const Locale('pt'));
  });

  test('fixadas primeiro; silenciadas não contam nas não lidas', () async {
    final groups = <GiftGroup>[];
    final list = [conv('a', hour: 9), conv('b', hour: 11), conv('c', hour: 8, pinned: true)];
    expect(
      [for (final i in conversationItems(groups, list, ConversationFilter.all)) (i as DirectItem).conversation.id],
      ['c', 'b', 'a'],
    );

    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(me),
        chatRepositoryProvider.overrideWithValue(
          FakeChat([
            conv('a', unread: 2),
            conv('b', unread: 5, mutedUntil: Conversation.mutedForever),
            conv('c', unread: 1, mutedUntil: DateTime.now().subtract(const Duration(hours: 1))), // já passou
          ]),
        ),
        chatEventsProvider.overrideWithValue(const Stream.empty()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(conversationsProvider, (_, _) {});
    await container.read(conversationsProvider.future);
    expect(container.read(unreadTotalProvider), 3);
  });

  group('Notificações de mensagens', () {
    late StreamController<ChatEvent> events;
    late List<(String, String, String)> shown;

    ProviderContainer make(UserProfile user, List<Conversation> conversations) {
      events = StreamController<ChatEvent>.broadcast();
      shown = [];
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(user),
          chatRepositoryProvider.overrideWithValue(FakeChat(conversations)),
          chatEventsProvider.overrideWithValue(events.stream),
          showChatNotificationProvider.overrideWithValue(({
            required conversationId,
            required title,
            required body,
          }) async {
            shown.add((conversationId, title, body));
          }),
        ],
      );
      addTearDown(() {
        container.dispose();
        events.close();
      });
      container.listen(chatNotificationsProvider, (_, _) {});
      return container;
    }

    test('avisa, exceto na conversa aberta, nas silenciadas e nas minhas mensagens', () async {
      final container = make(me, [
        conv('dm', title: 'Gil Costa'),
        conv('grupo', group: true, title: 'Prenda da Rita'),
        conv('calado', mutedUntil: Conversation.mutedForever),
      ]);
      await container.read(conversationsProvider.future);
      container.read(conversationsProvider.notifier).setOpen('aberta');

      events
        ..add(MessageReceived(incoming('dm')))
        ..add(MessageReceived(incoming('grupo', body: 'Encomendei!')))
        ..add(MessageReceived(incoming('calado')))
        ..add(MessageReceived(incoming('aberta')))
        ..add(MessageReceived(incoming('dm', sender: 'me')));
      await pumpEventQueue();
      expect(shown, [('dm', 'Gil Costa', 'Já compraste?'), ('grupo', 'Prenda da Rita', 'Gil: Encomendei!')]);
    });

    test('sem pré-visualização diz só "Nova mensagem"; desligadas não avisa', () async {
      final noPreview = make(me.copyWith(messagePreviews: false), [conv('dm', title: 'Gil Costa')]);
      await noPreview.read(conversationsProvider.future);
      events.add(MessageReceived(incoming('dm')));
      await pumpEventQueue();
      expect(shown, [('dm', 'Gil Costa', 'Nova mensagem')]);

      final off = make(me.copyWith(messageNotifications: false), [conv('dm')]);
      await off.read(conversationsProvider.future);
      events.add(MessageReceived(incoming('dm')));
      await pumpEventQueue();
      expect(shown, isEmpty);
    });
  });

  Widget app(FakeChat repo, Widget child) => ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(me),
      chatRepositoryProvider.overrideWithValue(repo),
      chatEventsProvider.overrideWithValue(const Stream.empty()),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: const [AppPalette.light]),
      home: Scaffold(body: child),
    ),
  );

  testWidgets('detalhes da conversa: silenciar "sempre" e fixar', (tester) async {
    final repo = FakeChat([conv('dm', title: 'Gil Costa')]);
    await tester.pumpWidget(app(repo, const ConversationInfoScreen(conversationId: 'dm')));
    await tester.pumpAndSettle();
    expect(find.text('Notificações ligadas'), findsOneWidget);

    await tester.tap(find.text('Silenciar notificações'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sempre'));
    await tester.pumpAndSettle();
    expect(repo.prefs.single, ('dm', Conversation.mutedForever, null));
    expect(find.text('Silenciada'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(repo.prefs.last, ('dm', null, true));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a caixa de mensagens do Início mostra as conversas por ler (sem as silenciadas)', (tester) async {
    final repo = FakeChat([
      conv('a', unread: 2, title: 'Ana Lopes'),
      conv('b', unread: 1, group: true, title: 'Prenda da Rita'),
      conv('c', unread: 4, title: 'Calado', mutedUntil: Conversation.mutedForever),
      conv('d', title: 'Lida'),
    ]);
    await tester.pumpWidget(app(repo, const SingleChildScrollView(child: HomeInbox())));
    await tester.pumpAndSettle();
    expect(find.text('Mensagens'), findsOneWidget);
    expect(find.text('3 mensagens por ler'), findsOneWidget);
    expect(find.text('Ana Lopes'), findsOneWidget);
    expect(find.text('Gil: Olá de b'), findsOneWidget);
    expect(find.text('Calado'), findsNothing);
    expect(find.text('Lida'), findsNothing);
  });

  testWidgets('sem nada por ler, a caixa de mensagens não aparece', (tester) async {
    await tester.pumpWidget(app(FakeChat([conv('d')]), const HomeInbox()));
    await tester.pumpAndSettle();
    expect(find.text('Mensagens'), findsNothing);
  });
}
