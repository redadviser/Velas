import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/errors.dart';
import '../models/models.dart';
import '../models/party_models.dart';
import '../repositories/party_repository.dart';

/// Festas no próprio dispositivo. Ficam numa só lista para que outra conta
/// local possa entrar com o código, como no servidor.
class LocalPartyRepository implements PartyRepository {
  LocalPartyRepository(this._prefs, this._profile);

  final SharedPreferences _prefs;
  final UserProfile Function() _profile;

  static const _key = 'velas.local.parties';
  static const _uuid = Uuid();

  String get _me => _profile().id;

  List<Party> _all() => ((jsonDecode(_prefs.getString(_key) ?? '[]') as List).cast<Map>())
      .map((e) => Party.fromJson(e.cast<String, dynamic>()))
      .toList();

  Future<void> _write(List<Party> all) => _prefs.setString(_key, jsonEncode(all.map((p) => p.toJson()).toList()));

  bool _member(Party p) => p.isHost(_me) || p.guestFor(_me) != null;

  Party _find(List<Party> all, String id) =>
      all.where((p) => p.id == id && _member(p)).firstOrNull ?? (throw const AppException('Esta festa já não existe.'));

  Future<Party> _replace(List<Party> all, Party p) async {
    await _write([for (final x in all) x.id == p.id ? p : x]);
    return p;
  }

  PartyGuest _self(Rsvp rsvp) {
    final me = _profile();
    return PartyGuest(
      id: _uuid.v4(),
      userId: me.id,
      name: me.name,
      username: me.username.isEmpty ? null : me.username,
      rsvp: rsvp,
    );
  }

  static String _code() {
    final r = Random.secure();
    return List.generate(10, (_) => '0123456789ABCDEF'[r.nextInt(16)]).join();
  }

  @override
  Future<List<Party>> fetchParties() async => _all().where(_member).toList();

  @override
  Future<Party> saveParty(Party party) async {
    final all = _all();
    final existing = all.where((p) => p.id == party.id).firstOrNull;
    if (existing == null) {
      final created = Party(
        id: party.id,
        createdBy: _me,
        title: party.title,
        celebrantName: party.celebrantName,
        personId: party.personId,
        startsAt: party.startsAt,
        place: party.place,
        notes: party.notes,
        inviteCode: _code(),
        guests: [_self(Rsvp.yes)],
      );
      await _write([...all, created]);
      return created;
    }
    if (!existing.isHost(_me)) throw const AppException('Só quem organiza pode alterar a festa.');
    return _replace(
      all,
      existing.copyWith(
        title: party.title,
        celebrantName: party.celebrantName,
        personId: () => party.personId,
        startsAt: () => party.startsAt,
        place: party.place,
        notes: party.notes,
      ),
    );
  }

  @override
  Future<void> deleteParty(String id) async => _write(_all().where((p) => !(p.id == id && p.isHost(_me))).toList());

  @override
  Future<Party> join(String code) async {
    final all = _all();
    final p = all.where((p) => p.inviteCode == code.trim().toUpperCase()).firstOrNull;
    if (p == null) throw const AppException('Não encontrámos nenhuma festa com esse código.');
    if (_member(p)) return p;
    return _replace(all, p.copyWith(guests: [...p.guests, _self(Rsvp.pending)]));
  }

  @override
  Future<Party> rsvp(String partyId, Rsvp rsvp) async {
    final all = _all();
    final p = _find(all, partyId);
    return _replace(all, p.copyWith(guests: [for (final g in p.guests) g.userId == _me ? g.copyWith(rsvp: rsvp) : g]));
  }

  @override
  Future<Party> addGuest(String partyId, String name) async {
    final all = _all();
    final p = _find(all, partyId);
    if (!p.isHost(_me)) throw const AppException('Só quem organiza pode acrescentar convidados.');
    return _replace(
      all,
      p.copyWith(
        guests: [
          ...p.guests,
          PartyGuest(id: _uuid.v4(), name: name.trim()),
        ],
      ),
    );
  }

  @override
  Future<void> removeGuest(String guestId) async {
    final all = _all();
    final p = all.where((p) => _member(p) && p.guest(guestId) != null).firstOrNull;
    if (p == null) return;
    final g = p.guest(guestId)!;
    if (g.userId == p.createdBy || !(p.isHost(_me) || g.userId == _me)) {
      throw const AppException('Não podes tirar este convidado.');
    }
    await _replace(
      all,
      p.copyWith(
        guests: p.guests.where((x) => x.id != guestId).toList(),
        tasks: [for (final t in p.tasks) t.assigneeId == guestId ? t.copyWith(assigneeId: () => null) : t],
      ),
    );
  }

  @override
  Future<Party> saveTask(String partyId, PartyTask task) async {
    final all = _all();
    final p = _find(all, partyId);
    final i = p.tasks.indexWhere((t) => t.id == task.id);
    return _replace(all, p.copyWith(tasks: i == -1 ? [...p.tasks, task] : ([...p.tasks]..[i] = task)));
  }

  @override
  Future<void> deleteTask(String partyId, String taskId) async {
    final all = _all();
    final p = _find(all, partyId);
    await _replace(all, p.copyWith(tasks: p.tasks.where((t) => t.id != taskId).toList()));
  }
}
