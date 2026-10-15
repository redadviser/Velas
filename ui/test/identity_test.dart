import 'package:aniversarios/core/config/env.dart';
import 'package:aniversarios/core/utils/identity.dart';
import 'package:aniversarios/data/local/local_auth_repository.dart';
import 'package:aniversarios/data/models/group_models.dart';
import 'package:aniversarios/features/groups/invite_links.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Username', () {
    test('normaliza e valida', () {
      expect(Identity.normalizeUsername('@Ana_S'), 'ana_s');
      expect(Identity.usernameError('ana.s'), isNull);
      expect(Identity.usernameError('ab'), isNotNull);
      expect(Identity.usernameError('.ana'), isNotNull);
      expect(Identity.usernameError('ana-s'), isNotNull);
      expect(Identity.usernameError('a' * 21), isNotNull);
    });
  });

  group('Telemóvel', () {
    test('converte para E.164', () {
      expect(Identity.toE164('912 345 678'), '+351912345678');
      expect(Identity.toE164('+351 936 000 111'), '+351936000111');
      expect(Identity.toE164('00351 961234567'), '+351961234567');
      expect(Identity.toE164('+44 7700 900123'), '+447700900123');
      expect(Identity.toE164('212345678'), isNull); // fixo português
      expect(Identity.toE164('+351 212 345 678'), isNull);
      expect(Identity.displayPhone('+351912345678'), '+351 912 345 678');
    });
  });

  test('distingue email, telemóvel e username', () {
    expect(Identity.kindOf('Ana@Ex.pt'), IdentifierKind.email);
    expect(Identity.normalizeIdentifier('Ana@Ex.pt'), 'ana@ex.pt');
    expect(Identity.kindOf('912345678'), IdentifierKind.phone);
    expect(Identity.normalizeIdentifier('912 345 678'), '+351912345678');
    expect(Identity.kindOf('@carla.m'), IdentifierKind.username);
    expect(Identity.kindOf('não sei'), IdentifierKind.invalid);
  });

  test('links de convite', () {
    expect(InviteLinks.codeFrom(Uri.parse('com.eupasoft.velas://app/join/ABCDE12345')), 'ABCDE12345');
    expect(InviteLinks.codeFrom(Uri.parse('https://convite.velas.pt/g/ABCDE12345')), 'ABCDE12345');
    expect(InviteLinks.codeFrom(Uri.parse('com.eupasoft.velas://auth-callback?code=x')), isNull);
    // Com servidor, o link partilhado é a página de convite da API.
    expect(InviteLinks.shareLink('ABC'), '${Env.apiUrl}/g/ABC');
  });

  test('códigos de convite: formato, o que a pessoa escreve e mensagens', () {
    expect(InviteLinks.formatCode('K7P2QX9M'), 'K7P2 QX9M');
    expect(InviteLinks.formatCode('ABCDE12345'), 'ABCDE12345'); // códigos antigos
    expect(InviteLinks.normalizeCode(' k7p2 qx9m '), 'K7P2QX9M');
    expect(InviteLinks.normalizeCode('K7P2-QX9M'), 'K7P2QX9M');
    expect(InviteLinks.normalizeCode('https://convite.velas.pt/g/K7P2QX9M'), 'K7P2QX9M');
    expect(InviteLinks.displayLink('K7P2QX9M'), endsWith('/g/K7P2QX9M'));
    expect(InviteLinks.displayLink('K7P2QX9M'), isNot(startsWith('http')));

    final g = GiftGroup(
      id: 'g1',
      createdBy: 'u1',
      title: 'Prenda para a Mãe',
      celebrantName: 'Helena',
      targetAmount: 80,
      inviteCode: 'K7P2QX9M',
      createdAt: DateTime(2026),
    );
    expect(InviteLinks.linkMessage(g), contains(InviteLinks.shareLink('K7P2QX9M')));
    expect(InviteLinks.codeMessage(g), contains('Código do grupo: K7P2 QX9M'));
    expect(InviteLinks.codeMessage(g), contains(InviteLinks.shareLink('K7P2QX9M')));
  });

  group('Conta local', () {
    late LocalAuthRepository auth;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      auth = LocalAuthRepository(await SharedPreferences.getInstance());
      await auth.init();
      await auth.signUp(
        name: 'Ana',
        username: 'Ana_S',
        email: 'ana@ex.pt',
        password: 'password1',
        phone: '+351912345678',
      );
      await auth.signOut();
    });

    test('entra com email ou username', () async {
      await auth.signIn(identifier: '@ana_s', password: 'password1');
      expect(auth.current!.username, 'ana_s');
      await auth.signOut();
      await auth.signIn(identifier: 'ANA@ex.pt', password: 'password1');
      expect(auth.current!.phone, '+351912345678');
    });

    test('username e telemóvel são únicos', () async {
      final check = await auth.checkAvailability(username: 'ana_s', phone: '+351912345678');
      expect(check.usernameTaken, isTrue);
      expect(check.phoneTaken, isTrue);
      expect(
        () => auth.signUp(name: 'B', username: 'ana_s', email: 'b@ex.pt', password: 'password1'),
        throwsA(anything),
      );
    });

    test('palavra-passe errada falha', () async {
      expect(() => auth.signIn(identifier: 'ana_s', password: 'errada123'), throwsA(anything));
    });
  });
}
