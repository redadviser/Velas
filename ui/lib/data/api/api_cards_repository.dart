import 'package:uuid/uuid.dart';

import '../../core/utils/errors.dart';
import '../models/card_models.dart';
import '../repositories/cards_repository.dart';
import 'api_client.dart';

/// Ver backend/src/modules/cards.
class ApiCardsRepository implements CardsRepository {
  ApiCardsRepository(this._api);

  final ApiClient _api;

  @override
  Future<SentCard> create({
    required String personId,
    required String recipientName,
    required String body,
    String? friendId,
  }) async {
    try {
      final res = await _api.post('/cards', {
        'id': const Uuid().v4(),
        'person_id': personId,
        'recipient_name': recipientName,
        'body': body,
        'recipient_id': ?friendId,
      });
      return SentCard.fromJson((res as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      if (e.code == 'not_friends') throw const AppException('Só podes publicar no mural dos teus amigos.');
      rethrow;
    }
  }

  @override
  Future<List<ReceivedCard>> received() async {
    final rows = (await _api.get('/cards/received')) as List;
    return [for (final r in rows) ReceivedCard.fromJson((r as Map).cast<String, dynamic>())];
  }

  @override
  Future<void> markWallSeen() => _api.post('/cards/received/seen');

  @override
  Future<List<SentCard>> sentTo(String personId) async {
    final rows = (await _api.get('/cards/sent?person_id=$personId')) as List;
    return [for (final r in rows) SentCard.fromJson((r as Map).cast<String, dynamic>())];
  }

  @override
  Future<GreetingCard> preview(String token) async {
    try {
      return GreetingCard.fromJson(((await _api.getPublic('/cards/$token')) as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      if (e.code == 'card_not_found' || e.code == 'validation_error') {
        throw const AppException('Este cartão já não existe. Pode ter sido apagado por quem o enviou.');
      }
      rethrow;
    }
  }

  @override
  Future<void> markOpened(String token) => _api.postPublic('/cards/$token/opened', const {});

  @override
  Future<ClaimedCard> claim(String token) async {
    try {
      final res = (await _api.post('/cards/$token/claim') as Map).cast<String, dynamic>();
      return ClaimedCard(senderId: res['sender_id'] as String, conversationId: res['conversation_id'] as String);
    } on ApiException catch (e) {
      if (e.code == 'card_claimed') throw const AppException('Este cartão já foi guardado noutra conta.');
      if (e.code == 'own_card') throw const AppException('Este cartão foi enviado por ti.');
      if (e.code == 'card_not_found') throw const AppException('Este cartão já não existe.');
      rethrow;
    }
  }
}
