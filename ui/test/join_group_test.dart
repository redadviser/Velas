import 'package:aniversarios/core/i18n/translations.dart';
import 'package:aniversarios/core/providers.dart';
import 'package:aniversarios/core/theme/app_colors.dart';
import 'package:aniversarios/data/models/group_models.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/data/repositories/group_repository.dart';
import 'package:aniversarios/features/groups/group_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

const me = UserProfile(id: 'me', email: 'eu@ex.pt', name: 'Eu');

class FakeGroups implements GroupRepository {
  final joined = <String>[];
  String? failWith;

  @override
  bool get supportsInvites => true;

  @override
  Future<List<GiftGroup>> fetchGroups() async => const [];

  @override
  Future<List<InvitationPreview>> myInvitations() async => const [];

  @override
  Future<String> joinByCode(String code, String displayName) async {
    if (failWith != null) throw Exception(failWith);
    joined.add(code);
    return 'g1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await Translations.load(const Locale('pt'));
  });

  Future<FakeGroups> open(WidgetTester tester) async {
    final repo = FakeGroups();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) =>
                  TextButton(onPressed: () => showJoinGroupSheet(context, ref), child: const Text('abrir')),
            ),
          ),
        ),
        GoRoute(path: '/groups/:id', builder: (_, s) => Scaffold(body: Text('grupo ${s.pathParameters['id']}'))),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentUserProvider.overrideWithValue(me), groupRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(theme: ThemeData(extensions: const [AppPalette.light]), routerConfig: router),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('entrar com código abre o grupo sem rebentar', (tester) async {
    final repo = await open(tester);
    await tester.enterText(find.byType(TextField), 'k7p2 qx9m');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repo.joined, ['K7P2QX9M']);
    expect(find.text('grupo g1'), findsOneWidget);
  });

  testWidgets('fechar a folha sem entrar também não rebenta', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'ABCD');
    await tester.tapAt(const Offset(10, 10)); // fora da folha
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('abrir'), findsOneWidget);
  });
}
