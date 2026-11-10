import '../models/party_models.dart';
import '../repositories/party_repository.dart';
import 'api_client.dart';

class ApiPartyRepository implements PartyRepository {
  ApiPartyRepository(this._api);

  final ApiClient _api;

  Party _party(dynamic j) => Party.fromJson((j as Map).cast<String, dynamic>());

  @override
  Future<List<Party>> fetchParties() async => ((await _api.get('/parties')) as List).map(_party).toList();

  @override
  Future<Party> saveParty(Party party) async => _party(await _api.put('/parties/${party.id}', party.toBody()));

  @override
  Future<void> deleteParty(String id) => _api.delete('/parties/$id');

  @override
  Future<Party> join(String code) async => _party(await _api.post('/parties/join', {'code': code}));

  @override
  Future<Party> rsvp(String partyId, Rsvp rsvp) async => _party(await _api.put('/parties/$partyId/rsvp', {'rsvp': rsvp.name}));

  @override
  Future<Party> addGuest(String partyId, String name) async => _party(await _api.post('/parties/$partyId/guests', {'name': name}));

  @override
  Future<void> removeGuest(String guestId) => _api.delete('/party-guests/$guestId');

  @override
  Future<Party> saveTask(String partyId, PartyTask task) async => _party(
    await _api.put('/parties/$partyId/tasks/${task.id}', {'title': task.title, 'assignee_id': task.assigneeId, 'done': task.done}),
  );

  @override
  Future<void> deleteTask(String partyId, String taskId) => _api.delete('/parties/$partyId/tasks/$taskId');
}
