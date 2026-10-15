import 'dart:async';
import 'dart:typed_data';

import 'package:aniversarios/core/chat_providers.dart';
import 'package:aniversarios/core/providers.dart';
import 'package:aniversarios/core/theme/app_colors.dart';
import 'package:aniversarios/data/api/chat_socket.dart';
import 'package:aniversarios/data/models/chat_models.dart';
import 'package:aniversarios/data/models/group_models.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/data/repositories/chat_repository.dart';
import 'package:aniversarios/features/chat/chat_screen.dart';
import 'package:aniversarios/features/chat/conversations_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

const me = UserProfile(id: 'me', email: 'eu@ex.pt', name: 'Eu Mesma');

ChatMessage msg(String id, {String sender = 'gil', String body = 'olá', int minute = 0, MessageKind kind = MessageKind.text}) =>
    ChatMessage(
      id: id,
      conversationId: 'c1',
      senderId: sender,
      senderName: sender == 'me' ? 'Eu Mesma' : 'Gil Costa',
      kind: kind,
      body: body,
      createdAt: DateTime(2026, 10, 15, 10, minute),
    );

class FakeChatRepository implements ChatRepository {
  final sent = <OutgoingMessage>[];
  final uploads = <Uint8List>[];
  final reads = <String>[];
  bool failNextSend = false;
  List<ChatMessage> page = [msg('m2', body: 'Um livro?', minute: 2), msg('m1', sender: 'me', body: 'O que oferecemos?', minute: 1)];

  @override
  Future<Conversation> fetchConversation(String id) async => Conversation(
    id: id,
    isGroup: false,
    title: 'Gil Costa',
    otherUser: const ChatUser(userId: 'gil', name: 'Gil Costa', username: 'gil'),
    createdAt: DateTime(2026),
    participants: [
      Participant(user: const ChatUser(userId: 'me', name: 'Eu Mesma')),
      Participant(user: const ChatUser(userId: 'gil', name: 'Gil Costa'), lastReadAt: DateTime(2026, 10, 15, 10, 1)),
    ],
  );

  @override
  Future<MessagePage> fetchMessages(String id, {String? before, int limit = 50}) async =>
      MessagePage(messages: before == null ? page : const [], hasMore: false);

  @override
  Future<String> uploadImage(String id, Uint8List bytes) async {
    uploads.add(bytes);
    return '$id/img.jpg';
  }

  @override
  Future<ChatMessage> sendMessage(String id, OutgoingMessage m) async {
    if (failNextSend) {
      failNextSend = false;
      throw Exception('sem rede');
    }
    sent.add(m);
    return ChatMessage(
      id: m.id,
      conversationId: id,
      senderId: 'me',
      senderName: 'Eu Mesma',
      kind: m.kind,
      body: m.body,
      mediaUrl: m.mediaKey == null ? m.mediaUrl : 'https://api.test/files/${m.mediaKey}',
      createdAt: DateTime(2026, 10, 15, 11),
    );
  }

  @override
  Future<ChatMessage> react(String messageId, String? emoji) async =>
      page.firstWhere((m) => m.id == messageId).copyWith(reactions: [if (emoji != null) Reaction(emoji: emoji, userId: 'me')]);

  @override
  Future<void> markRead(String id) async => reads.add(id);

  @override
  Future<List<Conversation>> fetchConversations() async => [await fetchConversation('c1')];

  @override
  Future<FriendsList> fetchFriends() async =>
      const FriendsList(friends: [ChatUser(userId: 'gil', name: 'Gil Costa', username: 'gil')]);

  @override
  Future<List<Sticker>> fetchStickers() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('pt_PT');
    Intl.defaultLocale = 'pt_PT';
  });

  group('Modelos', () {
    test('lê mensagens do servidor com resposta e reações', () {
      final m = ChatMessage.fromJson({
        'id': 'm1',
        'conversation_id': 'c1',
        'sender_id': 'u1',
        'sender_name': 'Filipa',
        'kind': 'image',
        'body': 'Este?',
        'media_url': 'https://api.test/files/c1/x.jpg',
        'width': 800,
        'height': 600,
        'reply': {'id': 'm0', 'sender_name': 'Gil', 'kind': 'text', 'body': 'Ideias?', 'deleted': false},
        'reactions': [
          {'emoji': '❤️', 'user_id': 'u2'},
          {'emoji': '❤️', 'user_id': 'u3'},
          {'emoji': '😂', 'user_id': 'u4'},
        ],
        'created_at': '2026-10-15T10:00:00.000Z',
        'deleted': false,
      });
      expect(m.kind, MessageKind.image);
      expect(m.aspectRatio, closeTo(1.333, 0.001));
      expect(m.reply!.senderName, 'Gil');
      expect(m.reactionGroups, {'❤️': ['u2', 'u3'], '😂': ['u4']});
      expect(m.reactionOf('u4'), '😂');
      expect(m.preview, '📷 Este?');
    });

    test('só emojis curtos aparecem em grande', () {
      expect(msg('a', body: '🎉').isBigEmoji, isTrue);
      expect(msg('a', body: '❤️ 👍🏽').isBigEmoji, isTrue);
      expect(msg('a', body: '👨‍👩‍👧').isBigEmoji, isTrue);
      expect(msg('a', body: '🎉🎉🎉🎉').isBigEmoji, isFalse);
      expect(msg('a', body: 'parabéns 🎉').isBigEmoji, isFalse);
      expect(msg('a', body: '1').isBigEmoji, isFalse);
    });

    test('a mensagem enviada só leva os campos usados', () {
      const out = OutgoingMessage(id: 'x', kind: MessageKind.sticker, stickerId: 's1', width: 10, height: 10);
      expect(out.toJson(), {'id': 'x', 'kind': 'sticker', 'body': '', 'sticker_id': 's1', 'width': 10, 'height': 10});
    });

    test('lê conversas e eventos em tempo real', () {
      final c = Conversation.fromJson({
        'id': 'c1',
        'kind': 'group',
        'group_id': 'g1',
        'title': 'Prenda da Rita',
        'celebrant_name': 'Rita',
        'other_user': null,
        'unread_count': 3,
        'last_message': {
          'id': 'm1',
          'sender_id': 'u1',
          'sender_name': 'Hugo',
          'kind': 'gif',
          'body': '',
          'created_at': '2026-10-15T10:00:00+00:00',
          'deleted': false,
        },
        'last_message_at': '2026-10-15T10:00:00+00:00',
        'created_at': '2026-10-01T10:00:00+00:00',
      });
      expect(c.isGroup, isTrue);
      expect(c.lastMessage!.preview, 'GIF');
      expect(c.unreadCount, 3);

      expect(parseChatEvent({'type': 'ready'}), isA<ChatConnected>());
      expect(parseChatEvent({'type': 'friends'}), isA<FriendsChanged>());
      final typing = parseChatEvent({'type': 'typing', 'conversation_id': 'c1', 'user_id': 'u1', 'name': 'Hugo'});
      expect(typing, isA<Typing>().having((t) => t.name, 'name', 'Hugo'));
      expect(parseChatEvent({'type': 'desconhecido'}), isNull);
    });

    test('junta mensagens pelo id, mais recentes primeiro', () {
      final merged = mergeMessages(
        [msg('b', minute: 2), msg('a', minute: 1)],
        [msg('c', minute: 3), msg('a', body: 'editada', minute: 1)],
      );
      expect(merged.map((m) => m.id), ['c', 'b', 'a']);
      expect(merged.last.body, 'editada');
    });
  });

  group('Lista de conversas', () {
    Conversation conv(String id, {bool group = false, int unread = 0, int? hour}) => Conversation(
      id: id,
      isGroup: group,
      title: id,
      unreadCount: unread,
      lastMessageAt: hour == null ? null : DateTime(2026, 10, 15, hour),
      createdAt: DateTime(2026, 10, 1),
    );
    GiftGroup gift(String id, {String? conversation, DateTime? created}) => GiftGroup(
      id: id,
      createdBy: 'me',
      title: id,
      celebrantName: 'Rita',
      targetAmount: 50,
      createdAt: created ?? DateTime(2026, 9, 1),
      conversationId: conversation,
    );

    final groups = [gift('prenda-rita', conversation: 'cg1'), gift('prenda-local', created: DateTime(2026, 10, 10))];
    final conversations = [conv('cg1', group: true, unread: 2, hour: 9), conv('gil', unread: 1, hour: 12), conv('ana', hour: 8)];

    List<String> ids(ConversationFilter f) => [
      for (final i in conversationItems(groups, conversations, f))
        switch (i) {
          GroupItem(:final group) => group.id,
          DirectItem(:final conversation) => conversation.id,
        },
    ];

    test('mistura prendas e conversas privadas pela atividade mais recente', () {
      // A conversa do grupo não aparece duas vezes: vem dentro da prenda.
      expect(ids(ConversationFilter.all), ['gil', 'prenda-rita', 'ana', 'prenda-local']);
    });

    test('filtra prendas, privadas e não lidas', () {
      expect(ids(ConversationFilter.gifts), ['prenda-rita', 'prenda-local']);
      expect(ids(ConversationFilter.direct), ['gil', 'ana']);
      expect(ids(ConversationFilter.unread), ['gil', 'prenda-rita']);
    });
  });

  group('ChatController', () {
    late FakeChatRepository repo;
    late StreamController<ChatEvent> events;
    late ProviderContainer container;

    setUp(() {
      repo = FakeChatRepository();
      events = StreamController<ChatEvent>.broadcast();
      container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(me),
          chatRepositoryProvider.overrideWithValue(repo),
          chatEventsProvider.overrideWithValue(events.stream),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      events.close();
    });

    Future<ChatController> open() async {
      container.listen(chatProvider('c1'), (_, _) {});
      final ctrl = container.read(chatProvider('c1').notifier);
      await pumpEventQueue();
      return ctrl;
    }

    ChatState state() => container.read(chatProvider('c1'));

    test('carrega a conversa e as mensagens', () async {
      await open();
      expect(state().loading, isFalse);
      expect(state().messages.map((m) => m.id), ['m2', 'm1']);
      expect(state().conversation!.participants, hasLength(2));
    });

    test('envia com atualização imediata e substitui pela do servidor', () async {
      final ctrl = await open();
      final future = ctrl.sendText('  Boa ideia!  ', replyTo: state().messages.first);
      expect(state().messages.first, isA<ChatMessage>().having((m) => m.state, 'state', SendState.sending));
      await future;
      expect(state().messages.first.state, SendState.sent);
      expect(state().messages.first.body, 'Boa ideia!');
      expect(repo.sent.single.replyTo, 'm2');
    });

    test('se falhar, fica marcada e pode ser reenviada sem carregar a imagem outra vez', () async {
      final ctrl = await open();
      repo.failNextSend = true;
      await expectLater(ctrl.sendImage(Uint8List.fromList([1, 2, 3]), width: 4, height: 3), throwsException);
      final failed = state().messages.first;
      expect(failed.state, SendState.failed);
      expect(failed.localBytes, isNotNull);
      expect(repo.uploads, hasLength(1));

      await ctrl.retry(failed);
      expect(repo.uploads, hasLength(1));
      expect(repo.sent.single.mediaKey, 'c1/img.jpg');
      expect(state().messages.first.state, SendState.sent);
      // A imagem local mantém-se até a do servidor carregar.
      expect(state().messages.first.localBytes, isNotNull);
    });

    test('aplica mensagens, reações, leituras e "a escrever" em tempo real', () async {
      final ctrl = await open();
      ctrl.setVisible(true);

      events.add(const Typing(conversationId: 'c1', userId: 'gil', name: 'Gil Costa'));
      await pumpEventQueue();
      expect(state().typing, {'gil': 'Gil Costa'});

      events.add(MessageReceived(msg('m3', body: 'Ou flores 💐', minute: 5)));
      // De outra conversa: ignorada.
      events.add(MessageReceived(ChatMessage(id: 'z', conversationId: 'outra', senderId: 'gil', createdAt: DateTime(2026))));
      await pumpEventQueue();
      expect(state().messages.first.id, 'm3');
      expect(state().messages.any((m) => m.id == 'z'), isFalse);
      // Quem enviou deixou de escrever.
      expect(state().typing, isEmpty);

      events.add(ReadReceipt(conversationId: 'c1', userId: 'gil', lastReadAt: DateTime(2026, 10, 15, 12)));
      await pumpEventQueue();
      expect(state().conversation!.participants.last.lastReadAt, DateTime(2026, 10, 15, 12));

      await ctrl.react(state().messages.firstWhere((m) => m.id == 'm2'), '❤️');
      expect(state().messages.firstWhere((m) => m.id == 'm2').reactionOf('me'), '❤️');

      // Com o ecrã aberto, o que chega fica lido.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(repo.reads, contains('c1'));
    });
  });

  testWidgets('o ecrã da conversa mostra mensagens, "visto" e a caixa de escrita', (tester) async {
    final repo = FakeChatRepository()
      ..page = [
        msg('m4', body: '🎉', minute: 4),
        ChatMessage(id: 'm3', conversationId: 'c1', senderId: 'gil', senderName: 'Gil Costa', deleted: true, createdAt: DateTime(2026, 10, 15, 10, 3)),
        msg('m2', sender: 'me', body: 'Combinado', minute: 1),
        msg('m1', body: 'Vamos oferecer um livro à Rita?'),
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(me),
          chatRepositoryProvider.overrideWithValue(repo),
          chatEventsProvider.overrideWithValue(const Stream.empty()),
          groupRepositoryProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppPalette.light]),
          home: const ChatScreen(conversationId: 'c1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gil Costa'), findsWidgets);
    expect(find.text('Vamos oferecer um livro à Rita?'), findsOneWidget);
    expect(find.text('🎉'), findsOneWidget);
    expect(find.text('Mensagem apagada'), findsOneWidget);
    // A minha mensagem foi lida pelo Gil (às 10:01).
    expect(find.byIcon(LucideIcons.checkCheck), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Escrever mostra o botão de enviar.
    await tester.enterText(find.byType(TextField), 'Sim!');
    await tester.pump();
    expect(find.byTooltip('Enviar'), findsOneWidget);
  });
}
