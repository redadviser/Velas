import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/api/api_chat_repository.dart';
import '../data/api/chat_socket.dart';
import '../data/models/chat_models.dart';
import '../data/repositories/chat_repository.dart';
import 'providers.dart';

/// Amigos e conversas só existem com servidor: `null` no modo local.
final chatRepositoryProvider = Provider<ChatRepository?>((ref) {
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  final api = ref.watch(apiClientProvider);
  if (userId == null || api == null) return null;
  return ApiChatRepository(api);
});

/// Ligação em tempo real, aberta enquanto houver sessão.
final chatSocketProvider = Provider<ChatSocket?>((ref) {
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  final api = ref.watch(apiClientProvider);
  if (userId == null || api == null) return null;
  final socket = ChatSocket(api)..start();
  // Em segundo plano o sistema pode cortar a ligação; ao voltar, liga outra vez.
  final lifecycle = AppLifecycleListener(onResume: socket.reconnect);
  ref.onDispose(() {
    lifecycle.dispose();
    socket.dispose();
  });
  return socket;
});

/// Eventos em tempo real (nada no modo local). Substituível nos testes.
final chatEventsProvider = Provider<Stream<ChatEvent>>(
  (ref) => ref.watch(chatSocketProvider)?.events ?? const Stream.empty(),
);

Stream<ChatEvent> _events(Ref ref) => ref.watch(chatEventsProvider);

// ---------------------------------------------------------------------------
// Conversas
// ---------------------------------------------------------------------------

class ConversationsController extends AsyncNotifier<List<Conversation>> {
  /// Conversa aberta no ecrã (as mensagens que chegam já estão lidas).
  String? _open;
  Timer? _refreshDebounce;

  @override
  Future<List<Conversation>> build() async {
    final repo = ref.watch(chatRepositoryProvider);
    if (repo == null) return const [];
    final sub = _events(ref).listen(_onEvent);
    ref.onDispose(() {
      sub.cancel();
      _refreshDebounce?.cancel();
    });
    return repo.fetchConversations();
  }

  String? get _me => ref.read(currentUserProvider)?.id;

  void _onEvent(ChatEvent e) {
    switch (e) {
      case MessageReceived(:final message):
        final list = state.value;
        final i = list?.indexWhere((c) => c.id == message.conversationId) ?? -1;
        if (list == null || i == -1) return _scheduleRefresh();
        final c = list[i];
        final unread = message.senderId != _me && _open != c.id ? c.unreadCount + 1 : c.unreadCount;
        final updated = c.copyWith(lastMessage: LastMessage.of(message), unreadCount: unread);
        state = AsyncData([updated, ...list.where((x) => x.id != c.id)]);
      case MessageUpdated(:final message):
        final list = state.value;
        if (list == null) return;
        state = AsyncData([
          for (final c in list)
            c.lastMessage?.id == message.id ? c.copyWith(lastMessage: LastMessage.of(message)) : c,
        ]);
      case ChatConnected() || ConversationsChanged():
        _scheduleRefresh();
      default:
        break;
    }
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 300), () => refresh().catchError((_) {}));
  }

  Future<void> refresh() async {
    final repo = ref.read(chatRepositoryProvider);
    if (repo == null) return;
    state = AsyncData(await repo.fetchConversations());
  }

  void setOpen(String? conversationId) => _open = conversationId;

  /// Atualiza a lista com o que o ecrã da conversa já sabe (ex.: mensagem enviada daqui).
  void applyLocal(ChatMessage message) => _onEvent(MessageReceived(message));

  Future<void> markRead(String conversationId) async {
    final list = state.value;
    if (list != null && list.any((c) => c.id == conversationId && c.unreadCount > 0)) {
      state = AsyncData([for (final c in list) c.id == conversationId ? c.copyWith(unreadCount: 0) : c]);
    }
    await ref.read(chatRepositoryProvider)?.markRead(conversationId);
  }

  /// Abre (ou cria) a conversa privada com um amigo e devolve o id.
  Future<String> openDirect(String userId) async {
    final c = await ref.read(chatRepositoryProvider)!.openDirect(userId);
    final list = state.value ?? const [];
    if (!list.any((x) => x.id == c.id)) state = AsyncData([c, ...list]);
    return c.id;
  }
}

final conversationsProvider = AsyncNotifierProvider<ConversationsController, List<Conversation>>(
  ConversationsController.new,
);

/// Mensagens por ler em todas as conversas (contador do separador).
final unreadTotalProvider = Provider<int>(
  (ref) => (ref.watch(conversationsProvider).value ?? const []).fold(0, (n, c) => n + c.unreadCount),
);

/// Não lidas da conversa de um grupo.
final groupUnreadProvider = Provider.family<int, String>(
  (ref, conversationId) =>
      ref.watch(conversationsProvider).value?.where((c) => c.id == conversationId).firstOrNull?.unreadCount ?? 0,
);

// ---------------------------------------------------------------------------
// Amigos
// ---------------------------------------------------------------------------

class FriendsController extends AsyncNotifier<FriendsList> {
  @override
  Future<FriendsList> build() async {
    final repo = ref.watch(chatRepositoryProvider);
    if (repo == null) return FriendsList.empty;
    final sub = _events(ref).listen((e) {
      if (e is FriendsChanged || e is ChatConnected) refresh().catchError((_) {});
    });
    ref.onDispose(sub.cancel);
    return repo.fetchFriends();
  }

  ChatRepository get _repo => ref.read(chatRepositoryProvider)!;

  Future<void> refresh() async => state = AsyncData(await _repo.fetchFriends());

  Future<FriendRequestResult> request(String userId) async {
    final r = await _repo.requestFriend(userId);
    await refresh();
    return r;
  }

  Future<void> respond(FriendRequest request, {required bool accept}) async {
    await _repo.respondFriendRequest(request.id, accept: accept);
    await refresh();
  }

  Future<void> remove(String userId) async {
    await _repo.removeFriend(userId);
    await refresh();
  }
}

final friendsProvider = AsyncNotifierProvider<FriendsController, FriendsList>(FriendsController.new);

final incomingFriendRequestsProvider = Provider<int>((ref) => ref.watch(friendsProvider).value?.incoming.length ?? 0);

// ---------------------------------------------------------------------------
// Stickers
// ---------------------------------------------------------------------------

class StickersController extends AsyncNotifier<List<Sticker>> {
  @override
  Future<List<Sticker>> build() async {
    final repo = ref.watch(chatRepositoryProvider);
    return repo == null ? const [] : repo.fetchStickers();
  }

  ChatRepository get _repo => ref.read(chatRepositoryProvider)!;

  Future<void> _add(Future<Sticker> Function() op) async {
    final s = await op();
    state = AsyncData([s, ...(state.value ?? const <Sticker>[]).where((x) => x.id != s.id)]);
  }

  Future<void> saveFromMessage(ChatMessage m) => _add(() => _repo.saveStickerFromMessage(m.id));
  Future<void> saveFromGif(Gif g) => _add(() => _repo.saveStickerFromGif(g));
  Future<void> upload(List<int> bytes, {int? width, int? height}) =>
      _add(() => _repo.uploadSticker(Uint8List.fromList(bytes), width: width, height: height));

  Future<void> delete(Sticker s) async {
    final previous = state.value;
    state = AsyncData([...?previous?.where((x) => x.id != s.id)]);
    try {
      await _repo.deleteSticker(s.id);
    } catch (_) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}

final stickersProvider = AsyncNotifierProvider<StickersController, List<Sticker>>(StickersController.new);

// ---------------------------------------------------------------------------
// Uma conversa
// ---------------------------------------------------------------------------

@immutable
class ChatState {
  const ChatState({
    this.conversation,
    this.messages = const [],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
    this.typing = const {},
  });

  /// Com os participantes.
  final Conversation? conversation;

  /// Mais recentes primeiro.
  final List<ChatMessage> messages;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;

  /// Quem está a escrever (id → nome).
  final Map<String, String> typing;

  ChatState copyWith({
    Conversation? conversation,
    List<ChatMessage>? messages,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Object? Function()? error,
    Map<String, String>? typing,
  }) => ChatState(
    conversation: conversation ?? this.conversation,
    messages: messages ?? this.messages,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    error: error != null ? error() : this.error,
    typing: typing ?? this.typing,
  );
}

/// Junta mensagens novas às que já existem (pelo id), mais recentes primeiro.
List<ChatMessage> mergeMessages(List<ChatMessage> current, Iterable<ChatMessage> incoming) {
  final byId = {for (final m in current) m.id: m};
  for (final m in incoming) {
    final old = byId[m.id];
    // Mantém a imagem local até a do servidor estar carregada (evita um "piscar").
    byId[m.id] = old?.localBytes != null ? m.copyWith(localBytes: () => old!.localBytes) : m;
  }
  return byId.values.toList()..sort((a, b) {
    final c = b.createdAt.compareTo(a.createdAt);
    return c != 0 ? c : b.id.compareTo(a.id);
  });
}

/// Mensagens de uma conversa: carrega por páginas, envia com atualização
/// imediata (e permite reenviar se falhar) e aplica os eventos em tempo real.
class ChatController extends Notifier<ChatState> {
  ChatController(this.conversationId);

  final String conversationId;

  static const _uuid = Uuid();
  static const _typingFor = Duration(seconds: 5);

  /// O que falta enviar das mensagens que falharam (para "tentar novamente").
  final _pending = <String, ({OutgoingMessage message, Uint8List? bytes})>{};
  final _typingTimers = <String, Timer>{};
  DateTime _lastTypingSent = DateTime(2000);
  Timer? _readDebounce;

  /// O ecrã está visível: as mensagens que chegam ficam lidas.
  bool visible = false;

  @override
  ChatState build() {
    final sub = _events(ref).listen(_onEvent);
    ref.onDispose(() {
      sub.cancel();
      _readDebounce?.cancel();
      for (final t in _typingTimers.values) {
        t.cancel();
      }
    });
    Future.microtask(load);
    return const ChatState();
  }

  ChatRepository get _repo => ref.read(chatRepositoryProvider)!;

  ({String id, String name}) get _me {
    final u = ref.read(currentUserProvider)!;
    return (id: u.id, name: u.name);
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, error: () => null);
    try {
      final (conv, page) = await (_repo.fetchConversation(conversationId), _repo.fetchMessages(conversationId)).wait;
      final local = state.messages.where((m) => m.state != SendState.sent);
      state = state.copyWith(
        conversation: conv,
        messages: mergeMessages(page.messages, local),
        hasMore: page.hasMore,
        loading: false,
      );
      _scheduleRead();
    } catch (e) {
      final err = e is ParallelWaitError ? (e.errors as (Object?, Object?)).$1 ?? e.errors.$2 : e;
      state = state.copyWith(loading: false, error: () => err);
    }
  }

  /// Depois de voltar a ligar: as mensagens recentes, sem perder as mais antigas já carregadas.
  Future<void> _catchUp() async {
    try {
      final page = await _repo.fetchMessages(conversationId);
      final known = state.messages.map((m) => m.id).toSet();
      // Sem sobreposição com o que já está carregado: houve um buraco, recomeça daqui.
      final overlaps = page.messages.any((m) => known.contains(m.id)) || state.messages.isEmpty;
      state = state.copyWith(
        messages: overlaps
            ? mergeMessages(state.messages, page.messages)
            : mergeMessages(page.messages, state.messages.where((m) => m.state != SendState.sent)),
        hasMore: overlaps ? state.hasMore : page.hasMore,
      );
      _scheduleRead();
    } catch (_) {
      // Fica para a próxima ligação.
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    final oldest = state.messages.lastWhere((m) => m.state == SendState.sent, orElse: () => state.messages.last);
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _repo.fetchMessages(conversationId, before: oldest.id);
      state = state.copyWith(messages: mergeMessages(state.messages, page.messages), hasMore: page.hasMore);
    } finally {
      state = state.copyWith(loadingMore: false);
    }
  }

  void _onEvent(ChatEvent e) {
    switch (e) {
      case MessageReceived(:final message) when message.conversationId == conversationId:
        _stopTyping(message.senderId);
        state = state.copyWith(messages: mergeMessages(state.messages, [message]));
        if (message.senderId != _me.id) _scheduleRead();
      case MessageUpdated(:final message) when message.conversationId == conversationId:
        if (state.messages.any((m) => m.id == message.id)) {
          state = state.copyWith(messages: mergeMessages(state.messages, [message]));
        }
      case ReadReceipt(:final userId, :final lastReadAt) when e.conversationId == conversationId:
        final conv = state.conversation;
        if (conv == null) return;
        state = state.copyWith(
          conversation: conv.copyWith(
            participants: [
              for (final p in conv.participants)
                p.user.userId == userId ? Participant(user: p.user, lastReadAt: lastReadAt) : p,
            ],
          ),
        );
      case Typing(:final userId, :final name) when e.conversationId == conversationId:
        _typingTimers[userId]?.cancel();
        _typingTimers[userId] = Timer(_typingFor, () => _stopTyping(userId));
        state = state.copyWith(typing: {...state.typing, userId: name});
      case ChatConnected():
        _catchUp();
      default:
        break;
    }
  }

  void _stopTyping(String? userId) {
    if (userId == null || !state.typing.containsKey(userId)) return;
    _typingTimers.remove(userId)?.cancel();
    state = state.copyWith(typing: {...state.typing}..remove(userId));
  }

  void _scheduleRead() {
    if (!visible) return;
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(conversationsProvider.notifier).markRead(conversationId).catchError((_) {});
    });
  }

  void setVisible(bool v) {
    visible = v;
    if (v) _scheduleRead();
  }

  /// Avisa os outros que estou a escrever (no máximo a cada 3 s).
  void typing() {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) < const Duration(seconds: 3)) return;
    _lastTypingSent = now;
    ref.read(chatSocketProvider)?.sendTyping(conversationId);
  }

  // Envio ------------------------------------------------------------------

  Future<void> sendText(String text, {ChatMessage? replyTo}) {
    final id = _uuid.v4();
    return _send(
      OutgoingMessage(id: id, kind: MessageKind.text, body: text.trim(), replyTo: replyTo?.id),
      replyTo: replyTo,
    );
  }

  Future<void> sendImage(Uint8List bytes, {int? width, int? height, String caption = '', ChatMessage? replyTo}) {
    final id = _uuid.v4();
    return _send(
      OutgoingMessage(id: id, kind: MessageKind.image, body: caption.trim(), width: width, height: height, replyTo: replyTo?.id),
      bytes: bytes,
      replyTo: replyTo,
    );
  }

  Future<void> sendGif(Gif gif, {bool asSticker = false, ChatMessage? replyTo}) => _send(
    OutgoingMessage(
      id: _uuid.v4(),
      kind: asSticker ? MessageKind.sticker : MessageKind.gif,
      mediaUrl: gif.url,
      width: gif.width,
      height: gif.height,
      replyTo: replyTo?.id,
    ),
    previewUrl: gif.url,
    replyTo: replyTo,
  );

  Future<void> sendSticker(Sticker s, {ChatMessage? replyTo}) => _send(
    OutgoingMessage(
      id: _uuid.v4(),
      kind: MessageKind.sticker,
      stickerId: s.id,
      width: s.width,
      height: s.height,
      replyTo: replyTo?.id,
    ),
    previewUrl: s.url,
    replyTo: replyTo,
  );

  Future<void> _send(OutgoingMessage out, {Uint8List? bytes, String? previewUrl, ChatMessage? replyTo}) async {
    final me = _me;
    final local = ChatMessage(
      id: out.id,
      conversationId: conversationId,
      senderId: me.id,
      senderName: me.name,
      kind: out.kind,
      body: out.body,
      mediaUrl: previewUrl,
      width: out.width,
      height: out.height,
      reply: replyTo == null ? null : MessageReply.of(replyTo),
      createdAt: DateTime.now(),
      state: SendState.sending,
      localBytes: bytes,
    );
    state = state.copyWith(messages: mergeMessages(state.messages, [local]));
    ref.read(conversationsProvider.notifier).applyLocal(local);
    await _deliver(out, bytes);
  }

  Future<void> _deliver(OutgoingMessage out, Uint8List? bytes) async {
    try {
      var message = out;
      if (bytes != null && out.mediaKey == null) {
        final key = await _repo.uploadImage(conversationId, bytes);
        message = OutgoingMessage(
          id: out.id,
          kind: out.kind,
          body: out.body,
          mediaKey: key,
          width: out.width,
          height: out.height,
          replyTo: out.replyTo,
        );
        // Se o envio falhar a seguir, não volta a carregar a imagem.
        _pending[out.id] = (message: message, bytes: bytes);
      }
      final sent = await _repo.sendMessage(conversationId, message);
      _pending.remove(out.id);
      state = state.copyWith(messages: mergeMessages(state.messages, [sent]));
    } catch (e) {
      _pending[out.id] = (message: _pending[out.id]?.message ?? out, bytes: bytes);
      state = state.copyWith(
        messages: [
          for (final m in state.messages) m.id == out.id ? m.copyWith(state: SendState.failed) : m,
        ],
      );
      rethrow;
    }
  }

  Future<void> retry(ChatMessage m) async {
    final p = _pending[m.id];
    if (p == null) return;
    state = state.copyWith(
      messages: [for (final x in state.messages) x.id == m.id ? x.copyWith(state: SendState.sending) : x],
    );
    await _deliver(p.message, p.bytes);
  }

  /// Desiste de uma mensagem que falhou.
  void discard(ChatMessage m) {
    _pending.remove(m.id);
    state = state.copyWith(messages: state.messages.where((x) => x.id != m.id).toList());
  }

  Future<void> delete(ChatMessage m) async {
    await _repo.deleteMessage(m.id);
    // O servidor envia a versão "apagada" por WebSocket; recarrega se não houver ligação.
    if (!(ref.read(chatSocketProvider)?.isConnected ?? false)) await _catchUp();
  }

  /// Escolher o mesmo emoji outra vez retira a reação.
  Future<void> react(ChatMessage m, String emoji) async {
    final me = _me.id;
    final next = m.reactionOf(me) == emoji ? null : emoji;
    final previous = m;
    final optimistic = m.copyWith(
      reactions: [...m.reactions.where((r) => r.userId != me), if (next != null) Reaction(emoji: next, userId: me)],
    );
    state = state.copyWith(messages: mergeMessages(state.messages, [optimistic]));
    try {
      final updated = await _repo.react(m.id, next);
      state = state.copyWith(messages: mergeMessages(state.messages, [updated]));
    } catch (_) {
      state = state.copyWith(messages: mergeMessages(state.messages, [previous]));
      rethrow;
    }
  }
}

final chatProvider = NotifierProvider.autoDispose.family<ChatController, ChatState, String>(ChatController.new);
