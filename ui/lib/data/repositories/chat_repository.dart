import 'dart:typed_data';

import '../models/chat_models.dart';

/// Amigos, conversas, stickers e GIFs. Só existe com servidor (no modo
/// local não há outras pessoas com quem falar).
abstract class ChatRepository {
  Future<FriendsList> fetchFriends();
  Future<FriendRequestResult> requestFriend(String userId);
  Future<void> respondFriendRequest(String requestId, {required bool accept});

  /// Remove um amigo ou cancela um pedido (feito ou recebido).
  Future<void> removeFriend(String userId);

  Future<List<Conversation>> fetchConversations();

  /// Uma conversa com os participantes (e até onde cada um leu).
  Future<Conversation> fetchConversation(String conversationId);

  /// Abre (ou cria) a conversa privada com um amigo.
  Future<Conversation> openDirect(String userId);

  Future<void> markRead(String conversationId);

  /// Silenciar ([mutedUntil], `null` = deixar de silenciar) e fixar, só para mim.
  /// Os parâmetros omitidos não mudam.
  Future<Conversation> setPrefs(String conversationId, {DateTime? Function()? mutedUntil, bool? pinned});

  /// Mais recentes primeiro; [before] pede as anteriores a essa mensagem.
  Future<MessagePage> fetchMessages(String conversationId, {String? before, int limit = 50});

  /// Envia a imagem e devolve a chave a usar em [sendMessage].
  Future<String> uploadImage(String conversationId, Uint8List bytes);

  Future<ChatMessage> sendMessage(String conversationId, OutgoingMessage message);
  Future<void> deleteMessage(String messageId);

  /// `null` retira a reação.
  Future<ChatMessage> react(String messageId, String? emoji);

  Future<List<Sticker>> fetchStickers();
  Future<Sticker> saveStickerFromMessage(String messageId);
  Future<Sticker> saveStickerFromGif(Gif gif);
  Future<Sticker> uploadSticker(Uint8List bytes, {int? width, int? height});
  Future<void> deleteSticker(String stickerId);

  /// Sem [query]: os mais populares.
  Future<GifPage> searchGifs(GifKind kind, String query, {int offset = 0});
}
