import 'package:aniversarios/data/local/local_auth_repository.dart';
import 'package:aniversarios/data/local/local_group_repository.dart';
import 'package:aniversarios/data/models/group_models.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

GroupMember member(String id, {String? userId, double? amount, int order = 0}) => GroupMember(
  id: id,
  groupId: 'g',
  name: id,
  userId: userId,
  customAmount: amount,
  createdAt: DateTime(2026, 1, 1, 0, order),
);

GiftGroup makeGroup(
  List<GroupMember> members, {
  double total = 100,
  SplitMode split = SplitMode.equal,
  String? buyer,
}) => GiftGroup(
  id: 'g',
  createdBy: 'admin-user',
  title: 'Prenda para a Mãe',
  celebrantName: 'Helena',
  targetAmount: total,
  splitMode: split,
  buyerMemberId: buyer,
  createdAt: DateTime(2026),
  members: members,
);

void main() {
  groupTests();
  paymentTests();
  repositoryTests();
}

void groupTests() {
  group('Divisão', () {
    test('divisão igual distribui os cêntimos e soma o total', () {
      final g = makeGroup([member('a', userId: 'admin-user', order: 0), member('b', order: 1), member('c', order: 2)]);
      expect(g.shares.values, [33.34, 33.33, 33.33]);
      expect(g.assignedTotal, closeTo(100, 0.001));
    });

    test('divisão personalizada usa o valor de cada um e mostra o que falta', () {
      final g = makeGroup([
        member('a', userId: 'admin-user', amount: 50),
        member('b', amount: 30, order: 1),
      ], split: SplitMode.custom);
      expect(g.shareOf(g.members[1]), 30);
      expect(g.unassigned, 20);
    });
  });

  group('Comprador e estados', () {
    test('sem comprador definido, compra o administrador', () {
      final g = makeGroup([member('a', userId: 'admin-user'), member('b', order: 1)]);
      expect(g.buyer!.id, 'a');
      expect(g.isAdminUser('admin-user'), isTrue);
    });

    test('a parte do comprador conta como recebida', () {
      final g = makeGroup([member('a', userId: 'admin-user'), member('b', order: 1)], buyer: 'b');
      expect(g.buyer!.id, 'b');
      expect(g.statusOf(g.members[1]), ContributionStatus.confirmed);
      expect(g.statusOf(g.members[0]), ContributionStatus.pending);
      expect(g.confirmedAmount, 50);
    });

    test('pago vs. confirmado', () {
      final paid = member('b', order: 1).copyWith(paidAt: () => DateTime.now(), paidMethod: () => PaymentMethod.mbway);
      final confirmed = member('c', order: 2).copyWith(paidAt: () => DateTime.now(), confirmedAt: () => DateTime.now());
      final g = makeGroup([member('a', userId: 'admin-user'), paid, confirmed], total: 90);
      expect(g.statusOf(paid), ContributionStatus.paid);
      expect(g.awaitingConfirmationCount, 1);
      expect(g.confirmedAmount, 60); // administrador (comprador) + c
      expect(g.reportedAmount, 90);
      expect(g.fullyCollected, isFalse);
    });

    test('serialização preserva membros e estado', () {
      final g = makeGroup([
        member('a', userId: 'admin-user'),
        member('b', order: 1).copyWith(paidAt: () => DateTime.utc(2026, 5, 1), paidMethod: () => PaymentMethod.revolut),
      ], buyer: 'a');
      final json = {...g.toJson(), 'group_members': g.members.map((m) => m.toJson()).toList()};
      final back = GiftGroup.fromJson(json);
      expect(back.members.length, 2);
      expect(back.members[1].paidMethod, PaymentMethod.revolut);
      expect(back.buyerMemberId, 'a');
    });
  });
}

void paymentTests() {
  group('Dados de pagamento', () {
    test('telemóvel português com ou sem indicativo', () {
      expect(PaymentFormat.normalizePhone('912 345 678'), '912345678');
      expect(PaymentFormat.normalizePhone('+351 936 000 111'), '936000111');
      expect(PaymentFormat.normalizePhone('212345678'), isNull); // fixo
      expect(PaymentFormat.normalizePhone('91234567'), isNull);
    });

    test('IBAN válido e inválido (mod-97)', () {
      expect(PaymentFormat.normalizeIban('PT50 0002 0123 1234 5678 9015 4'), 'PT50000201231234567890154');
      expect(PaymentFormat.normalizeIban('PT50 0002 0123 1234 5678 9015 5'), isNull);
      expect(PaymentFormat.normalizeIban('GB82 WEST 1234 5698 7654 32'), 'GB82WEST12345698765432');
    });

    test('métodos disponíveis seguem os dados preenchidos', () {
      const p = PaymentDetails(mbwayPhone: '912345678', paypalUser: 'ana', acceptsCash: false);
      expect(p.methods, [PaymentMethod.mbway, PaymentMethod.paypal]);
      expect(PaymentDetails.fromJson(p.toJson()).methods, p.methods);
    });
  });
}

void repositoryTests() {
  group('Repositório local', () {
    late LocalGroupRepository repo;
    const me = UserProfile(
      id: 'admin-user',
      email: 'eu@exemplo.pt',
      name: 'Eu',
      payment: PaymentDetails(mbwayPhone: '912345678'),
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repo = LocalGroupRepository(await SharedPreferences.getInstance(), () => me);
    });

    test('criar, pagar, confirmar e comprar', () async {
      final g = makeGroup([]);
      await repo.saveGroup(
        g,
        newMembers: [
          member('a', userId: 'admin-user'),
          member('b', order: 1),
        ],
      );
      var saved = (await repo.fetchGroups()).single;
      expect(saved.members.length, 2);
      expect((await repo.fetchPayee(saved)).mbwayPhone, '912345678');

      final b = saved.members.firstWhere((m) => m.id == 'b');
      await repo.setPaid(b, PaymentMethod.mbway);
      saved = (await repo.fetchGroups()).single;
      expect(saved.statusOf(saved.members.firstWhere((m) => m.id == 'b')), ContributionStatus.paid);

      await repo.setConfirmed(b, true);
      await repo.setPurchased('g', true);
      saved = (await repo.fetchGroups()).single;
      expect(saved.fullyCollected, isTrue);
      expect(saved.purchasedAt, isNotNull);
    });

    test('remover o comprador volta a pôr o administrador como comprador', () async {
      await repo.saveGroup(
        makeGroup([], buyer: 'b'),
        newMembers: [
          member('a', userId: 'admin-user'),
          member('b', order: 1),
        ],
      );
      final saved = (await repo.fetchGroups()).single;
      await repo.removeMember(saved.members.firstWhere((m) => m.id == 'b'));
      final after = (await repo.fetchGroups()).single;
      expect(after.buyer!.id, 'a');
    });

    test('convite por username entre duas contas do dispositivo', () async {
      final prefs = await SharedPreferences.getInstance();
      final auth = LocalAuthRepository(prefs);
      await auth.init();
      await auth.signUp(name: 'Ana', username: 'ana', email: 'ana@ex.pt', password: 'password1');
      final ana = auth.current!;
      await auth.signUp(name: 'Ana', username: 'ana.silva', email: 'ana2@ex.pt', password: 'password1');
      final ana2 = auth.current!;

      var current = ana;
      final repo = LocalGroupRepository(prefs, () => current);
      await repo.saveGroup(
        GiftGroup(
          id: 'g',
          createdBy: ana.id,
          title: 'Prenda',
          celebrantName: 'Helena',
          targetAmount: 50,
          createdAt: DateTime(2026),
        ),
        newMembers: [
          GroupMember(id: 'm1', groupId: 'g', name: 'Ana', userId: ana.id, username: 'ana', createdAt: DateTime(2026)),
        ],
      );

      // Nome repetido não basta: procura-se pelo username, que é único.
      expect(await repo.findUser('ana.silva'), isA<FoundUser>().having((u) => u.userId, 'id', ana2.id));
      expect(await repo.findUser('ninguem'), isNull);
      expect(await repo.inviteUser('g', ana2.id), InviteResult.invited);
      expect(await repo.inviteUser('g', ana2.id), InviteResult.alreadyInvited);
      expect((await repo.fetchGroups()).single.invitations.single.username, 'ana.silva');

      // A segunda conta vê o convite mas ainda não o grupo.
      current = ana2;
      expect(await repo.fetchGroups(), isEmpty);
      final inbox = await repo.myInvitations();
      expect(inbox.single.inviterName, 'Ana');
      expect(() => repo.inviteUser('g', ana.id), throwsA(anything)); // não é admin

      expect(await repo.respondInvitation(inbox.single.id, accept: true), 'g');
      final g = (await repo.fetchGroups()).single;
      expect(g.members.map((m) => m.username), containsAll(['ana', 'ana.silva']));
      expect(g.invitations, isEmpty);
      expect(await repo.myInvitations(), isEmpty);
    });

    test('entrar pelo código do link', () async {
      final prefs = await SharedPreferences.getInstance();
      final auth = LocalAuthRepository(prefs);
      await auth.init();
      await auth.signUp(name: 'Bruno', username: 'bruno', email: 'b@ex.pt', password: 'password1');
      final bruno = auth.current!;
      await repo.saveGroup(makeGroup([]), newMembers: [member('a', userId: 'admin-user')]);
      final code = (await repo.fetchGroups()).single.inviteCode;
      expect(code.length, 10);

      final asBruno = LocalGroupRepository(prefs, () => bruno);
      final preview = await asBruno.previewByCode(code.toLowerCase());
      expect(preview.alreadyMember, isFalse);
      expect(await asBruno.joinByCode(code, 'Bruno'), 'g');
      expect((await asBruno.fetchGroups()).single.members.length, 2);
      expect(() => asBruno.previewByCode('ERRADO'), throwsA(anything));
    });
  });
}
