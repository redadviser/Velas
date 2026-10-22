import 'dart:typed_data';

import '../models/card_models.dart';

/// Cartões de parabéns (links com a mensagem). Só com servidor.
abstract class CardsRepository {
  /// Cria o cartão (link) para a mensagem preparada para uma pessoa. Com
  /// [friendId], publica-o diretamente no mural desse amigo.
  Future<SentCard> create({
    required String personId,
    required String recipientName,
    required String body,
    String? friendId,
    String? mediaKey,
  });

  /// Fotografia, vídeo ou áudio de um cartão especial (Birthdayly+). Devolve o
  /// media_key para [create].
  Future<String> uploadMedia(Uint8List bytes);

  /// Cartões enviados a uma pessoa, mais recentes primeiro.
  Future<List<SentCard>> sentTo(String personId);

  /// O meu mural: cartões recebidos, mais recentes primeiro.
  Future<List<ReceivedCard>> received();

  /// Abri o mural: quem enviou os cartões fica a saber que foram vistos.
  Future<void> markWallSeen();

  /// Ver o cartão pelo link. Não precisa de sessão.
  Future<GreetingCard> preview(String token);

  /// Marca como aberto por quem o recebeu. Não precisa de sessão.
  Future<void> markOpened(String token);

  /// Guarda o cartão na conta: fica amigo de quem enviou e abre a conversa.
  Future<ClaimedCard> claim(String token);
}
