import 'chat_models.dart';

/// Cartão especial (Birthdayly+): uma fotografia, um vídeo ou um áudio.
enum CardMediaKind {
  image,
  video,
  audio;

  static CardMediaKind? parse(Object? v) => values.where((k) => k.name == v).firstOrNull;
}

/// A fotografia, o vídeo ou o áudio de um cartão.
typedef CardMedia = ({CardMediaKind kind, String url});

CardMedia? _media(Map<String, dynamic> j) {
  final kind = CardMediaKind.parse(j['media_kind']);
  final url = j['media_url'] as String?;
  return kind == null || url == null ? null : (kind: kind, url: url);
}

/// Cartão de parabéns visto por quem tem o link (com ou sem conta).
class GreetingCard {
  const GreetingCard({
    required this.token,
    required this.senderId,
    required this.senderName,
    required this.recipientName,
    required this.body,
    required this.createdAt,
    this.senderPhotoUrl,
    this.claimed = false,
    this.media,
  });

  final String token;
  final CardMedia? media;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final String recipientName;
  final String body;
  final DateTime createdAt;

  /// Já foi guardado na app (por quem o recebeu).
  final bool claimed;

  String get senderFirstName => senderName.trim().split(RegExp(r'\s+')).first;

  factory GreetingCard.fromJson(Map<String, dynamic> j) => GreetingCard(
    token: j['token'] as String,
    senderId: j['sender_id'] as String,
    senderName: j['sender_name'] as String? ?? '',
    senderPhotoUrl: j['sender_photo_url'] as String?,
    recipientName: j['recipient_name'] as String? ?? '',
    body: j['body'] as String? ?? '',
    createdAt: DateTime.parse(j['created_at'] as String),
    claimed: j['claimed'] as bool? ?? false,
    media: _media(j),
  );
}

/// Cartão enviado, com o estado para quem o enviou.
class SentCard {
  const SentCard({
    required this.id,
    required this.token,
    required this.recipientName,
    required this.body,
    required this.createdAt,
    this.onWall = false,
    this.openedAt,
    this.claimedAt,
    this.media,
  });

  final CardMedia? media;

  final String id;
  final String token;
  final String recipientName;
  final String body;

  /// Publicado diretamente no mural de um amigo (sem link).
  final bool onWall;
  final DateTime createdAt;
  final DateTime? openedAt;
  final DateTime? claimedAt;

  factory SentCard.fromJson(Map<String, dynamic> j) => SentCard(
    id: j['id'] as String,
    token: j['token'] as String,
    recipientName: j['recipient_name'] as String? ?? '',
    body: j['body'] as String? ?? '',
    onWall: j['via'] == 'wall',
    media: _media(j),
    createdAt: DateTime.parse(j['created_at'] as String),
    openedAt: _date(j['opened_at']),
    claimedAt: _date(j['claimed_at']),
  );

  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
}

/// Cartão no mural de quem o recebeu.
class ReceivedCard {
  const ReceivedCard({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
    this.seen = true,
    this.media,
  });

  final CardMedia? media;

  final String id;
  final ChatUser sender;
  final String body;

  /// Quando chegou ao mural.
  final DateTime receivedAt;

  /// `false` enquanto o mural não for aberto (os novos aparecem em destaque).
  final bool seen;

  factory ReceivedCard.fromJson(Map<String, dynamic> j) {
    final s = (j['sender'] as Map).cast<String, dynamic>();
    return ReceivedCard(
      id: j['id'] as String,
      sender: ChatUser(
        userId: s['user_id'] as String,
        name: s['display_name'] as String? ?? '',
        username: s['username'] as String? ?? '',
        photoUrl: s['photo_url'] as String?,
      ),
      body: j['body'] as String? ?? '',
      receivedAt: DateTime.parse(j['received_at'] as String).toLocal(),
      seen: j['seen'] as bool? ?? true,
      media: _media(j),
    );
  }
}

/// Resultado de guardar um cartão recebido.
class ClaimedCard {
  const ClaimedCard({required this.senderId, required this.conversationId});

  final String senderId;

  /// Conversa privada com quem enviou, que já começa com a mensagem do cartão.
  final String conversationId;
}
