import '../models/party_models.dart';

/// Festas surpresa (as regras de quem pode o quê estão no servidor; o modo
/// local segue as mesmas).
abstract class PartyRepository {
  Future<List<Party>> fetchParties();

  /// Cria ou atualiza (só quem organiza).
  Future<Party> saveParty(Party party);
  Future<void> deleteParty(String id);

  /// Entra com o código de convite.
  Future<Party> join(String code);
  Future<Party> rsvp(String partyId, Rsvp rsvp);

  /// Convidado sem conta (só quem organiza).
  Future<Party> addGuest(String partyId, String name);

  /// Tirar um convidado ou sair da festa.
  Future<void> removeGuest(String guestId);

  Future<Party> saveTask(String partyId, PartyTask task);
  Future<void> deleteTask(String partyId, String taskId);
}
