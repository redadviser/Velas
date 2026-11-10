import 'package:aniversarios/core/utils/errors.dart';
import 'package:aniversarios/data/local/local_party_repository.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/data/models/party_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const ana = UserProfile(id: 'ana', email: 'ana@ex.pt', name: 'Ana', username: 'ana');
  const rui = UserProfile(id: 'rui', email: 'rui@ex.pt', name: 'Rui');
  const ze = UserProfile(id: 'ze', email: 'ze@ex.pt', name: 'Zé');

  late SharedPreferences prefs;
  LocalPartyRepository as(UserProfile u) => LocalPartyRepository(prefs, () => u);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('quem cria vai; os outros entram pelo código e só os membros veem a festa', () async {
    final created = await as(ana).saveParty(
      const Party(id: 'f1', createdBy: 'ignorado', title: 'Jantar surpresa', celebrantName: 'Pedro'),
    );
    expect(created.createdBy, 'ana');
    expect(created.guests.single.rsvp, Rsvp.yes);
    expect(created.inviteCode, matches(RegExp(r'^[0-9A-F]{10}$')));
    expect(await as(rui).fetchParties(), isEmpty);

    final joined = await as(rui).join(created.inviteCode.toLowerCase());
    expect(joined.guestFor('rui')!.rsvp, Rsvp.pending);
    expect((await as(rui).rsvp('f1', Rsvp.maybe)).guestFor('rui')!.rsvp, Rsvp.maybe);
    await expectLater(as(rui).join('NAOEXISTE'), throwsA(isA<AppException>()));
    await expectLater(as(rui).saveParty(created.copyWith(title: 'X')), throwsA(isA<AppException>()));
    await expectLater(as(ze).rsvp('f1', Rsvp.yes), throwsA(isA<AppException>()));
  });

  test('convidados sem conta, tarefas e quem pode tirar quem', () async {
    final p = await as(ana).saveParty(const Party(id: 'f1', createdBy: '', title: 'Festa', celebrantName: 'Pedro'));
    await as(rui).join(p.inviteCode);
    await expectLater(as(rui).addGuest('f1', 'Tia Rosa'), throwsA(isA<AppException>()));
    final withAunt = await as(ana).addGuest('f1', 'Tia Rosa');
    final aunt = withAunt.guests.firstWhere((g) => g.name == 'Tia Rosa');
    expect(aunt.userId, isNull);

    final t = await as(rui).saveTask('f1', PartyTask(id: 't1', title: 'Bolo', assigneeId: aunt.id));
    expect(t.tasks.single.assigneeId, aunt.id);
    expect((await as(ana).saveTask('f1', t.tasks.single.copyWith(done: true))).doneTasks, 1);

    await expectLater(as(rui).removeGuest(aunt.id), throwsA(isA<AppException>()));
    final host = withAunt.guestFor('ana')!;
    await expectLater(as(ana).removeGuest(host.id), throwsA(isA<AppException>()));
    // Tirar a tia deixa a tarefa sem responsável.
    await as(ana).removeGuest(aunt.id);
    expect((await as(ana).fetchParties()).single.tasks.single.assigneeId, isNull);
    // O Rui sai; só a Ana apaga.
    await as(rui).removeGuest((await as(rui).fetchParties()).single.guestFor('rui')!.id);
    expect(await as(rui).fetchParties(), isEmpty);
    await as(rui).deleteParty('f1');
    expect(await as(ana).fetchParties(), hasLength(1));
    await as(ana).deleteParty('f1');
    expect(await as(ana).fetchParties(), isEmpty);
  });

  test('lê a festa no formato do servidor', () {
    final p = Party.fromJson({
      'id': 'f1',
      'created_by': 'ana',
      'title': 'Festa',
      'celebrant_name': 'Pedro',
      'person_id': null,
      'starts_at': '2026-05-24T18:30:00.000Z',
      'place': 'Lisboa',
      'notes': '',
      'invite_code': 'ABCDEF1234',
      'guests': [
        {'id': 'g1', 'user_id': 'ana', 'display_name': 'Ana', 'username': 'ana', 'rsvp': 'yes', 'created_at': '2026-01-01T00:00:00Z'},
        {'id': 'g2', 'user_id': null, 'display_name': 'Tia', 'username': null, 'rsvp': 'outra', 'created_at': '2026-01-01T00:00:00Z'},
      ],
      'tasks': [
        {'id': 't1', 'title': 'Bolo', 'assignee_id': 'g2', 'done': false, 'created_at': '2026-01-01T00:00:00Z'},
      ],
    });
    expect(p.startsAt!.isUtc, isFalse);
    expect(p.count(Rsvp.yes), 1);
    expect(p.guest('g2')!.rsvp, Rsvp.pending); // valor desconhecido = por responder
    expect(p.guest(p.tasks.single.assigneeId)!.name, 'Tia');
    expect(p.toBody().keys, containsAll(['title', 'celebrant_name', 'starts_at', 'place', 'notes', 'person_id']));
  });
}
