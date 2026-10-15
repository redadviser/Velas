import 'dart:typed_data';

import '../../core/constants.dart';
import '../../core/i18n/translations.dart';
import '../../core/utils/errors.dart';
import '../models/chat_models.dart';
import '../repositories/chat_repository.dart';
import 'api_client.dart';

/// Ver backend/src/modules/chat e backend/src/modules/friends.
class ApiChatRepository implements ChatRepository {
  ApiChatRepository(this._api);

  final ApiClient _api;

  static Map<String, dynamic> _map(Object? v) => (v as Map).cast<String, dynamic>();

  @override
  Future<FriendsList> fetchFriends() async => FriendsList.fromJson(_map(await _api.get('/friends')));

  @override
  Future<FriendRequestResult> requestFriend(String userId) async =>
      friendRequestResultFrom(_map(await _api.post('/friends/requests', {'user_id': userId}))['result'] as String?);

  @override
  Future<void> respondFriendRequest(String requestId, {required bool accept}) async {
    try {
      await _api.post('/friends/requests/$requestId/respond', {'accept': accept});
    } on ApiException catch (e) {
      if (e.code == 'friend_request_not_found') throw AppException(tr(Keys.errorFriendRequestGone));
      rethrow;
    }
  }

  @override
  Future<void> removeFriend(String userId) => _api.delete('/friends/$userId');

  @override
  Future<List<Conversation>> fetchConversations() async => [
    for (final c in (await _api.get('/conversations')) as List) Conversation.fromJson(_map(c)),
  ];

  @override
  Future<Conversation> fetchConversation(String conversationId) async =>
      Conversation.fromJson(_map(await _api.get('/conversations/$conversationId')));

  @override
  Future<Conversation> openDirect(String userId) async {
    try {
      return Conversation.fromJson(_map(await _api.post('/conversations/direct', {'user_id': userId})));
    } on ApiException catch (e) {
      if (e.code == 'not_friends') throw AppException(tr(Keys.errorDirectOnlyFriends));
      rethrow;
    }
  }

  @override
  Future<void> markRead(String conversationId) => _api.post('/conversations/$conversationId/read');

  @override
  Future<Conversation> setPrefs(String conversationId, {DateTime? Function()? mutedUntil, bool? pinned}) async {
    final body = {
      if (mutedUntil != null) 'muted_until': mutedUntil()?.toUtc().toIso8601String(),
      'pinned': ?pinned,
    };
    return Conversation.fromJson(_map(await _api.patch('/conversations/$conversationId/prefs', body)));
  }

  @override
  Future<MessagePage> fetchMessages(String conversationId, {String? before, int limit = 50}) async {
    final query = before == null ? '?limit=$limit' : '?limit=$limit&before=$before';
    return MessagePage.fromJson(_map(await _api.get('/conversations/$conversationId/messages$query')));
  }

  @override
  Future<String> uploadImage(String conversationId, Uint8List bytes) async {
    final res = _map(await _api.postBytes('/conversations/$conversationId/uploads', bytes, 'application/octet-stream'));
    return res['media_key'] as String;
  }

  @override
  Future<ChatMessage> sendMessage(String conversationId, OutgoingMessage message) async {
    try {
      return ChatMessage.fromJson(_map(await _api.post('/conversations/$conversationId/messages', message.toJson())));
    } on ApiException catch (e) {
      if (e.code == 'not_friends') throw AppException(tr(Keys.errorNotFriendsAnymore));
      rethrow;
    }
  }

  @override
  Future<void> deleteMessage(String messageId) => _api.delete('/chat-messages/$messageId');

  @override
  Future<ChatMessage> react(String messageId, String? emoji) async =>
      ChatMessage.fromJson(_map(await _api.put('/chat-messages/$messageId/reaction', {'emoji': emoji})));

  @override
  Future<List<Sticker>> fetchStickers() async => [
    for (final s in (await _api.get('/stickers')) as List) Sticker.fromJson(_map(s)),
  ];

  Future<Sticker> _saveSticker(Object body) async {
    try {
      return Sticker.fromJson(_map(await _api.post('/stickers', body)));
    } on ApiException catch (e) {
      if (e.code == 'too_many_stickers') throw AppException(tr(Keys.errorTooManyStickers));
      rethrow;
    }
  }

  @override
  Future<Sticker> saveStickerFromMessage(String messageId) => _saveSticker({'message_id': messageId});

  @override
  Future<Sticker> saveStickerFromGif(Gif gif) =>
      _saveSticker({'media_url': gif.url, 'width': gif.width, 'height': gif.height});

  @override
  Future<Sticker> uploadSticker(Uint8List bytes, {int? width, int? height}) async {
    final query = width != null && height != null ? '?width=$width&height=$height' : '';
    try {
      return Sticker.fromJson(_map(await _api.postBytes('/stickers/upload$query', bytes, 'application/octet-stream')));
    } on ApiException catch (e) {
      if (e.code == 'too_many_stickers') throw AppException(tr(Keys.errorTooManyStickers));
      rethrow;
    }
  }

  @override
  Future<void> deleteSticker(String stickerId) => _api.delete('/stickers/$stickerId');

  @override
  Future<GifPage> searchGifs(GifKind kind, String query, {int offset = 0}) async {
    final q = Uri(queryParameters: {'q': query, 'type': kind.name, 'offset': '$offset'}).query;
    try {
      return GifPage.fromJson(_map(await _api.get('/gifs?$q')));
    } on ApiException catch (e) {
      if (e.code == 'gifs_unavailable') throw AppException(tr(Keys.errorGifsUnavailable));
      rethrow;
    }
  }
}
