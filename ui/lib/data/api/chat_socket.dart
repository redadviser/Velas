import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/chat_models.dart';
import 'api_client.dart';

/// Evento recebido do servidor (ver backend/src/core/realtime.ts).
sealed class ChatEvent {
  const ChatEvent();
}

/// Ligação (re)estabelecida: convém recarregar o que possa ter sido perdido.
class ChatConnected extends ChatEvent {
  const ChatConnected();
}

class MessageReceived extends ChatEvent {
  const MessageReceived(this.message);
  final ChatMessage message;
}

/// Mensagem alterada (reação, apagada).
class MessageUpdated extends ChatEvent {
  const MessageUpdated(this.message);
  final ChatMessage message;
}

class ReadReceipt extends ChatEvent {
  const ReadReceipt({required this.conversationId, required this.userId, required this.lastReadAt, this.name = ''});
  final String conversationId;
  final String userId;
  final String name;
  final DateTime lastReadAt;
}

/// Alguém ficou online ou offline.
class PresenceChanged extends ChatEvent {
  const PresenceChanged({required this.userId, required this.online, this.lastSeenAt});
  final String userId;
  final bool online;
  final DateTime? lastSeenAt;
}

class Typing extends ChatEvent {
  const Typing({required this.conversationId, required this.userId, required this.name});
  final String conversationId;
  final String userId;
  final String name;
}

class ConversationsChanged extends ChatEvent {
  const ConversationsChanged();
}

class FriendsChanged extends ChatEvent {
  const FriendsChanged();
}

/// Cartões de parabéns: um enviado foi aberto/guardado, ou chegou um ao mural.
class CardsChanged extends ChatEvent {
  const CardsChanged();
}

/// Os dados mudaram fora da app (ex.: alguém deixou o aniversário pelo link).
class DataChanged extends ChatEvent {
  const DataChanged();
}

ChatEvent? parseChatEvent(Map<String, dynamic> j) {
  Map<String, dynamic> m() => (j['message'] as Map).cast<String, dynamic>();
  return switch (j['type']) {
    'ready' => const ChatConnected(),
    'message' => MessageReceived(ChatMessage.fromJson(m())),
    'message_updated' => MessageUpdated(ChatMessage.fromJson(m())),
    'read' => ReadReceipt(
      conversationId: j['conversation_id'] as String,
      userId: j['user_id'] as String,
      name: j['name'] as String? ?? '',
      lastReadAt: DateTime.parse(j['last_read_at'] as String).toLocal(),
    ),
    'presence' => PresenceChanged(
      userId: j['user_id'] as String,
      online: j['online'] as bool? ?? false,
      lastSeenAt: j['last_seen_at'] == null ? null : DateTime.parse(j['last_seen_at'] as String).toLocal(),
    ),
    'typing' => Typing(
      conversationId: j['conversation_id'] as String,
      userId: j['user_id'] as String,
      name: j['name'] as String? ?? '',
    ),
    'conversations' => const ConversationsChanged(),
    'friends' => const FriendsChanged(),
    'cards' => const CardsChanged(),
    'data' => const DataChanged(),
    _ => null,
  };
}

/// Ligação WebSocket com o servidor. Só avisa que há novidades: os dados
/// continuam a ser lidos e escritos pela API REST. Volta a ligar sozinha
/// (com espera crescente) se a ligação cair.
class ChatSocket {
  ChatSocket(this._api, {WebSocketChannel Function(Uri uri)? connect}) : _connect = connect ?? WebSocketChannel.connect;

  final ApiClient _api;
  final WebSocketChannel Function(Uri uri) _connect;

  final _events = StreamController<ChatEvent>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;
  bool _closed = false;
  bool _ready = false;
  bool _renewToken = false;
  bool _opening = false;

  Stream<ChatEvent> get events => _events.stream;

  bool get isConnected => _ready;

  Uri get _uri {
    final base = Uri.parse(_api.baseUrl);
    return base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '${base.path}/ws');
  }

  /// Liga (se ainda não estiver ligado).
  void start() {
    _closed = false;
    if (_channel == null && _retry == null && !_opening) _open();
  }

  /// Ao voltar à app: a ligação pode ter morrido em segundo plano.
  void reconnect() {
    _teardown();
    _attempt = 0;
    start();
  }

  Future<void> _open() async {
    _retry = null;
    _opening = true;
    final token = await _api.accessToken(renew: _renewToken).catchError((_) => null);
    _opening = false;
    _renewToken = false;
    if (_closed || _channel != null) return;
    if (token == null) return _scheduleRetry();

    try {
      final channel = _connect(_uri);
      _channel = channel;
      await channel.ready;
      if (_closed || _channel != channel) return;
      channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      _sub = channel.stream.listen(
        _onData,
        onDone: () => _onClosed(channel.closeCode),
        onError: (_) => _onClosed(null),
        cancelOnError: true,
      );
    } catch (_) {
      _onClosed(null);
    }
  }

  void _onData(dynamic raw) {
    try {
      final event = parseChatEvent((jsonDecode(raw as String) as Map).cast<String, dynamic>());
      if (event == null) return;
      if (event is ChatConnected) {
        _ready = true;
        _attempt = 0;
      }
      _events.add(event);
    } catch (_) {
      // Evento de uma versão mais recente do servidor: ignora.
    }
  }

  void _onClosed(int? code) {
    _teardown();
    // 4401: token recusado (provavelmente expirou) — pede outro antes de voltar a ligar.
    if (code == 4401) _renewToken = true;
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_closed || _retry != null) return;
    final seconds = min(30, pow(2, _attempt++).toInt());
    _retry = Timer(Duration(seconds: seconds), _open);
  }

  void _teardown() {
    _ready = false;
    _retry?.cancel();
    _retry = null;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void sendTyping(String conversationId) {
    if (!_ready) return;
    _channel?.sink.add(jsonEncode({'type': 'typing', 'conversation_id': conversationId}));
  }

  void dispose() {
    _closed = true;
    _teardown();
    _events.close();
  }
}
