import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

DateTime? _dt(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
int? _int(Object? v) => (v as num?)?.toInt();

/// Outra conta, com o mínimo para a reconhecer.
@immutable
class ChatUser {
  const ChatUser({required this.userId, required this.name, this.username = '', this.photoUrl});

  final String userId;
  final String name;
  final String username;
  final String? photoUrl;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    return (parts.length == 1 ? first : first + parts.last.characters.first).toUpperCase();
  }

  factory ChatUser.fromJson(Map<String, dynamic> j) => ChatUser(
    userId: j['user_id'] as String,
    name: j['display_name'] as String? ?? '',
    username: j['username'] as String? ?? '',
    photoUrl: j['photo_url'] as String?,
  );
}

// ---------------------------------------------------------------------------
// Amigos
// ---------------------------------------------------------------------------

@immutable
class FriendRequest {
  const FriendRequest({required this.id, required this.user, required this.createdAt});

  final String id;
  final ChatUser user;
  final DateTime createdAt;

  factory FriendRequest.fromJson(Map<String, dynamic> j) => FriendRequest(
    id: j['id'] as String,
    user: ChatUser.fromJson(j),
    createdAt: _dt(j['created_at']) ?? DateTime.now(),
  );
}

@immutable
class FriendsList {
  const FriendsList({this.friends = const [], this.incoming = const [], this.outgoing = const []});

  final List<ChatUser> friends;

  /// Pedidos que me fizeram.
  final List<FriendRequest> incoming;

  /// Pedidos que fiz, ainda sem resposta.
  final List<FriendRequest> outgoing;

  static const empty = FriendsList();

  bool isFriend(String userId) => friends.any((f) => f.userId == userId);

  factory FriendsList.fromJson(Map<String, dynamic> j) => FriendsList(
    friends: [for (final f in (j['friends'] as List?) ?? const []) ChatUser.fromJson((f as Map).cast())],
    incoming: [for (final r in (j['incoming'] as List?) ?? const []) FriendRequest.fromJson((r as Map).cast())],
    outgoing: [for (final r in (j['outgoing'] as List?) ?? const []) FriendRequest.fromJson((r as Map).cast())],
  );
}

enum FriendRequestResult { sent, accepted, alreadyFriends, alreadySent, notFound, self }

FriendRequestResult friendRequestResultFrom(String? v) => switch (v) {
  'sent' => FriendRequestResult.sent,
  'accepted' => FriendRequestResult.accepted,
  'already_friends' => FriendRequestResult.alreadyFriends,
  'already_sent' => FriendRequestResult.alreadySent,
  'self' => FriendRequestResult.self,
  _ => FriendRequestResult.notFound,
};

// ---------------------------------------------------------------------------
// Mensagens
// ---------------------------------------------------------------------------

enum MessageKind { text, image, gif, sticker }

MessageKind _kind(Object? v) => MessageKind.values.firstWhere((k) => k.name == v, orElse: () => MessageKind.text);

/// Estado de uma mensagem enviada daqui e ainda não confirmada pelo servidor.
enum SendState { sent, sending, failed }

@immutable
class Reaction {
  const Reaction({required this.emoji, required this.userId});

  final String emoji;
  final String userId;

  factory Reaction.fromJson(Map<String, dynamic> j) =>
      Reaction(emoji: j['emoji'] as String, userId: j['user_id'] as String);
}

/// Resumo da mensagem a que se responde.
@immutable
class MessageReply {
  const MessageReply({required this.id, required this.senderName, required this.kind, this.body = '', this.deleted = false});

  final String id;
  final String senderName;
  final MessageKind kind;
  final String body;
  final bool deleted;

  factory MessageReply.fromJson(Map<String, dynamic> j) => MessageReply(
    id: j['id'] as String,
    senderName: j['sender_name'] as String? ?? '',
    kind: _kind(j['kind']),
    body: j['body'] as String? ?? '',
    deleted: j['deleted'] as bool? ?? false,
  );

  factory MessageReply.of(ChatMessage m) =>
      MessageReply(id: m.id, senderName: m.senderName, kind: m.kind, body: m.body, deleted: m.deleted);
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.senderName = '',
    this.senderPhotoUrl,
    this.kind = MessageKind.text,
    this.body = '',
    this.mediaUrl,
    this.width,
    this.height,
    this.reply,
    this.reactions = const [],
    required this.createdAt,
    this.deleted = false,
    this.state = SendState.sent,
    this.localBytes,
  });

  final String id;
  final String conversationId;

  /// `null` quando a conta foi eliminada.
  final String? senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final MessageKind kind;
  final String body;
  final String? mediaUrl;
  final int? width;
  final int? height;
  final MessageReply? reply;
  final List<Reaction> reactions;
  final DateTime createdAt;
  final bool deleted;

  /// Só nas mensagens enviadas daqui.
  final SendState state;

  /// Imagem ainda a carregar (mostrada enquanto o envio não termina).
  final Uint8List? localBytes;

  bool get hasMedia => kind != MessageKind.text;

  /// Proporção da imagem (largura / altura), se conhecida.
  double? get aspectRatio => width != null && height != null && height! > 0 ? width! / height! : null;

  /// Texto só com 1 a 3 emojis: mostrado em grande, sem balão.
  bool get isBigEmoji {
    if (kind != MessageKind.text || deleted) return false;
    final t = body.trim();
    if (t.isEmpty || t.characters.length > 3) return false;
    return _emojiOnly.hasMatch(t);
  }

  // ignore: valid_regexps — o analisador não conhece \p{Extended_Pictographic}, mas o Dart suporta.
  static final _emojiOnly = RegExp(r'^(?:\p{Extended_Pictographic}|‍|️|[\u{1F3FB}-\u{1F3FF}]|\s)+$', unicode: true);

  /// Resumo de uma linha (lista de conversas, respostas).
  String get preview => previewOf(kind, body, deleted: deleted);

  static String previewOf(MessageKind kind, String body, {bool deleted = false}) {
    if (deleted) return 'Mensagem apagada';
    return switch (kind) {
      MessageKind.text => body,
      MessageKind.image => body.isEmpty ? '📷 Fotografia' : '📷 $body',
      MessageKind.gif => 'GIF',
      MessageKind.sticker => 'Sticker',
    };
  }

  /// Reações agrupadas por emoji, pela ordem em que apareceram.
  Map<String, List<String>> get reactionGroups {
    final map = <String, List<String>>{};
    for (final r in reactions) {
      (map[r.emoji] ??= []).add(r.userId);
    }
    return map;
  }

  String? reactionOf(String userId) => reactions.where((r) => r.userId == userId).firstOrNull?.emoji;

  ChatMessage copyWith({
    SendState? state,
    List<Reaction>? reactions,
    String? mediaUrl,
    Uint8List? Function()? localBytes,
  }) => ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    senderName: senderName,
    senderPhotoUrl: senderPhotoUrl,
    kind: kind,
    body: body,
    mediaUrl: mediaUrl ?? this.mediaUrl,
    width: width,
    height: height,
    reply: reply,
    reactions: reactions ?? this.reactions,
    createdAt: createdAt,
    deleted: deleted,
    state: state ?? this.state,
    localBytes: localBytes != null ? localBytes() : this.localBytes,
  );

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'] as String,
    conversationId: j['conversation_id'] as String,
    senderId: j['sender_id'] as String?,
    senderName: j['sender_name'] as String? ?? '',
    senderPhotoUrl: j['sender_photo_url'] as String?,
    kind: _kind(j['kind']),
    body: j['body'] as String? ?? '',
    mediaUrl: j['media_url'] as String?,
    width: _int(j['width']),
    height: _int(j['height']),
    reply: j['reply'] == null ? null : MessageReply.fromJson((j['reply'] as Map).cast()),
    reactions: [for (final r in (j['reactions'] as List?) ?? const []) Reaction.fromJson((r as Map).cast())],
    createdAt: _dt(j['created_at']) ?? DateTime.now(),
    deleted: j['deleted'] as bool? ?? false,
  );
}

/// O que se envia (ver POST /conversations/:id/messages).
@immutable
class OutgoingMessage {
  const OutgoingMessage({
    required this.id,
    required this.kind,
    this.body = '',
    this.mediaKey,
    this.mediaUrl,
    this.stickerId,
    this.width,
    this.height,
    this.replyTo,
  });

  final String id;
  final MessageKind kind;
  final String body;
  final String? mediaKey;
  final String? mediaUrl;
  final String? stickerId;
  final int? width;
  final int? height;
  final String? replyTo;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'body': body,
    'media_key': ?mediaKey,
    'media_url': ?mediaUrl,
    'sticker_id': ?stickerId,
    'width': ?width,
    'height': ?height,
    'reply_to': ?replyTo,
  };
}

// ---------------------------------------------------------------------------
// Conversas
// ---------------------------------------------------------------------------

@immutable
class LastMessage {
  const LastMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.deleted = false,
  });

  final String id;
  final String? senderId;
  final String senderName;
  final MessageKind kind;
  final String body;
  final DateTime createdAt;
  final bool deleted;

  String get preview => ChatMessage.previewOf(kind, body, deleted: deleted);

  factory LastMessage.fromJson(Map<String, dynamic> j) => LastMessage(
    id: j['id'] as String,
    senderId: j['sender_id'] as String?,
    senderName: j['sender_name'] as String? ?? '',
    kind: _kind(j['kind']),
    body: j['body'] as String? ?? '',
    createdAt: _dt(j['created_at']) ?? DateTime.now(),
    deleted: j['deleted'] as bool? ?? false,
  );

  factory LastMessage.of(ChatMessage m) => LastMessage(
    id: m.id,
    senderId: m.senderId,
    senderName: m.senderName,
    kind: m.kind,
    body: m.body,
    createdAt: m.createdAt,
    deleted: m.deleted,
  );
}

@immutable
class Participant {
  const Participant({required this.user, this.lastReadAt});

  final ChatUser user;
  final DateTime? lastReadAt;

  factory Participant.fromJson(Map<String, dynamic> j) =>
      Participant(user: ChatUser.fromJson(j), lastReadAt: _dt(j['last_read_at']));
}

@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.isGroup,
    this.groupId,
    required this.title,
    this.celebrantName,
    this.otherUser,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    required this.createdAt,
    this.participants = const [],
  });

  final String id;
  final bool isGroup;
  final String? groupId;

  /// Título do grupo ou nome da outra pessoa.
  final String title;
  final String? celebrantName;
  final ChatUser? otherUser;
  final LastMessage? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime createdAt;

  /// Só em GET /conversations/:id.
  final List<Participant> participants;

  DateTime get sortKey => lastMessageAt ?? createdAt;

  Conversation copyWith({LastMessage? lastMessage, int? unreadCount, List<Participant>? participants}) => Conversation(
    id: id,
    isGroup: isGroup,
    groupId: groupId,
    title: title,
    celebrantName: celebrantName,
    otherUser: otherUser,
    lastMessage: lastMessage ?? this.lastMessage,
    lastMessageAt: lastMessage?.createdAt ?? lastMessageAt,
    unreadCount: unreadCount ?? this.unreadCount,
    createdAt: createdAt,
    participants: participants ?? this.participants,
  );

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
    id: j['id'] as String,
    isGroup: j['kind'] == 'group',
    groupId: j['group_id'] as String?,
    title: j['title'] as String? ?? '',
    celebrantName: j['celebrant_name'] as String?,
    otherUser: j['other_user'] == null ? null : ChatUser.fromJson((j['other_user'] as Map).cast()),
    lastMessage: j['last_message'] == null ? null : LastMessage.fromJson((j['last_message'] as Map).cast()),
    lastMessageAt: _dt(j['last_message_at']),
    unreadCount: _int(j['unread_count']) ?? 0,
    createdAt: _dt(j['created_at']) ?? DateTime.now(),
    participants: [for (final p in (j['participants'] as List?) ?? const []) Participant.fromJson((p as Map).cast())],
  );
}

/// Página de mensagens (mais recentes primeiro).
@immutable
class MessagePage {
  const MessagePage({required this.messages, required this.hasMore});

  final List<ChatMessage> messages;
  final bool hasMore;

  factory MessagePage.fromJson(Map<String, dynamic> j) => MessagePage(
    messages: [for (final m in (j['messages'] as List?) ?? const []) ChatMessage.fromJson((m as Map).cast())],
    hasMore: j['has_more'] as bool? ?? false,
  );
}

// ---------------------------------------------------------------------------
// Stickers e GIFs
// ---------------------------------------------------------------------------

@immutable
class Sticker {
  const Sticker({required this.id, required this.url, this.width, this.height});

  final String id;
  final String url;
  final int? width;
  final int? height;

  factory Sticker.fromJson(Map<String, dynamic> j) => Sticker(
    id: j['id'] as String,
    url: j['url'] as String,
    width: _int(j['width']),
    height: _int(j['height']),
  );
}

enum GifKind { gifs, stickers }

@immutable
class Gif {
  const Gif({required this.id, required this.url, required this.previewUrl, required this.width, required this.height});

  final String id;
  final String url;
  final String previewUrl;
  final int width;
  final int height;

  factory Gif.fromJson(Map<String, dynamic> j) => Gif(
    id: j['id'] as String,
    url: j['url'] as String,
    previewUrl: j['preview_url'] as String,
    width: _int(j['width']) ?? 1,
    height: _int(j['height']) ?? 1,
  );
}

@immutable
class GifPage {
  const GifPage({required this.results, this.nextOffset});

  final List<Gif> results;
  final int? nextOffset;

  factory GifPage.fromJson(Map<String, dynamic> j) => GifPage(
    results: [for (final g in (j['results'] as List?) ?? const []) Gif.fromJson((g as Map).cast())],
    nextOffset: _int(j['next_offset']),
  );
}
