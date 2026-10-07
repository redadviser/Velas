import 'package:aniversarios/core/providers.dart';
import 'package:aniversarios/core/theme/app_theme.dart';
import 'package:aniversarios/data/local/local_group_repository.dart';
import 'package:aniversarios/data/models/group_models.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/data/repositories/group_repository.dart';
import 'package:aniversarios/features/groups/invite_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _me = UserProfile(id: 'me', email: 'eu@ex.pt', name: 'Eu');

class _FakeRepo extends LocalGroupRepository {
  _FakeRepo(super.prefs, super.profile);
  final searched = <String>[];

  @override
  bool get supportsInvites => true;

  @override
  Future<FoundUser?> findUser(String identifier) async {
    searched.add(identifier);
    return identifier == 'ines@ex.pt' ? const FoundUser(userId: 'u1', name: 'Inês Duarte', username: 'inesd') : null;
  }
}

Future<_FakeRepo> _pump(WidgetTester tester, Future<String> Function(FoundUser) onAction) async {
  SharedPreferences.setMockInitialValues({});
  final repo = _FakeRepo(await SharedPreferences.getInstance(), () => _me);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(_me),
        groupRepositoryProvider.overrideWithValue(repo as GroupRepository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ContactLookup(actionLabel: 'Convidar', onAction: onAction, onShareLink: () {}),
        ),
      ),
    ),
  );
  return repo;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('email sem conta mostra que não existe conta', (tester) async {
    final repo = await _pump(tester, (_) async => '');
    await tester.enterText(find.byType(TextField), 'Ninguem@Ex.pt');
    await tester.tap(find.text('Procurar'));
    await tester.pumpAndSettle();
    expect(repo.searched, ['ninguem@ex.pt']);
    expect(find.text('Não existe nenhuma conta com este email.'), findsOneWidget);
    expect(find.text('Partilhar link de convite'), findsOneWidget);
  });

  testWidgets('telemóvel sem conta usa a mensagem de telemóvel', (tester) async {
    final repo = await _pump(tester, (_) async => '');
    await tester.enterText(find.byType(TextField), '912 345 678');
    await tester.tap(find.text('Procurar'));
    await tester.pumpAndSettle();
    expect(repo.searched, ['+351912345678']);
    expect(find.text('Não existe nenhuma conta com este número de telemóvel.'), findsOneWidget);
  });

  testWidgets('conta encontrada mostra a pessoa e convida', (tester) async {
    FoundUser? invited;
    await _pump(tester, (u) async {
      invited = u;
      return 'Convite enviado a ${u.name}.';
    });
    await tester.enterText(find.byType(TextField), 'ines@ex.pt');
    await tester.tap(find.text('Procurar'));
    await tester.pumpAndSettle();
    expect(find.text('Inês Duarte'), findsOneWidget);
    expect(find.text('@inesd'), findsOneWidget);
    await tester.tap(find.text('Convidar'));
    await tester.pumpAndSettle();
    expect(invited?.userId, 'u1');
    expect(find.text('Convite enviado a Inês Duarte.'), findsOneWidget);
  });

  testWidgets('texto inválido não chega a procurar', (tester) async {
    final repo = await _pump(tester, (_) async => '');
    await tester.enterText(find.byType(TextField), 'não sei');
    await tester.tap(find.text('Procurar'));
    await tester.pumpAndSettle();
    expect(repo.searched, isEmpty);
    expect(find.textContaining('Escreve um email'), findsOneWidget);
  });
}
