import 'package:aniversarios/core/chat_providers.dart';
import 'package:aniversarios/core/i18n/translations.dart';
import 'package:aniversarios/core/providers.dart';
import 'package:aniversarios/core/theme/app_colors.dart';
import 'package:aniversarios/data/models/chat_models.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/data/repositories/chat_repository.dart';
import 'package:aniversarios/features/people/linked_friend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const me = UserProfile(id: 'me', email: 'eu@ex.pt', name: 'Eu');
const ana = ChatUser(userId: 'ana', name: 'Ana Silva', username: 'ana.silva');
const anaCosta = ChatUser(userId: 'ana2', name: 'Ana Costa');
const rui = ChatUser(userId: 'rui', name: 'Rui Gomes', username: 'rui');

class FakeChat implements ChatRepository {
  FakeChat(this.friends);

  final List<ChatUser> friends;

  @override
  Future<FriendsList> fetchFriends() async => FriendsList(friends: friends);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Translations.load(const Locale('pt'));
  });

  test('sugere o amigo pelo nome só quando não há dúvida', () {
    expect(matchingFriend('Ana Silva', [ana, anaCosta, rui]), ana);
    expect(matchingFriend('ana', [ana, anaCosta, rui]), isNull); // duas Anas
    expect(matchingFriend('Rui', [ana, rui]), rui);
    expect(matchingFriend('Mãe', [ana, rui]), isNull);
    expect(matchingFriend('', [ana]), isNull);
  });

  test('a ligação vai e vem no JSON da pessoa', () {
    final p = Person(id: 'p1', name: 'Ana', day: 1, month: 2, linkedUserId: 'ana', createdAt: DateTime(2026));
    expect(p.toJson()['linked_user_id'], 'ana');
    expect(Person.fromJson(p.toJson()).linkedUserId, 'ana');
    expect(p.copyWith(linkedUserId: () => null).linkedUserId, isNull);
  });

  Future<List<String?>> pump(WidgetTester tester, {String? linked, String name = 'Ana Silva', List<Person> people = const []}) async {
    final changes = <String?>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(me),
          chatRepositoryProvider.overrideWithValue(FakeChat([ana, anaCosta, rui])),
          chatEventsProvider.overrideWithValue(const Stream.empty()),
          dataProvider.overrideWithValue(AppData.empty.copyWith(people: people)),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppPalette.light]),
          home: Scaffold(
            body: ListView(
              children: [LinkedFriendField(linkedUserId: linked, personName: name, onChanged: changes.add)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return changes;
  }

  testWidgets('sugere o amigo com o mesmo nome e liga-o', (tester) async {
    final changes = await pump(tester);
    expect(find.text('Ana Silva está na Birthdayly. É esta pessoa?'), findsOneWidget);
    await tester.tap(find.text('Ligar'));
    expect(changes, ['ana']);
  });

  testWidgets('escolhe outro amigo da lista, sem os já ligados a outros aniversários', (tester) async {
    final other = Person(id: 'p2', name: 'Rui', day: 1, month: 1, linkedUserId: 'rui', createdAt: DateTime(2026));
    final changes = await pump(tester, name: 'Mãe', people: [other]);
    expect(find.textContaining('está na Birthdayly'), findsNothing);
    await tester.tap(find.text('Ligar a um amigo da Birthdayly'));
    await tester.pumpAndSettle();
    expect(find.text('Rui Gomes'), findsNothing);
    await tester.tap(find.text('Ana Costa'));
    await tester.pumpAndSettle();
    expect(changes, ['ana2']);
  });

  testWidgets('mostra o amigo ligado e deixa desligar', (tester) async {
    final changes = await pump(tester, linked: 'ana');
    expect(find.text('@ana.silva'), findsOneWidget);
    await tester.tap(find.byTooltip('Desligar'));
    expect(changes, [null]);
  });
}
