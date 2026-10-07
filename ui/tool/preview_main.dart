// TEMPORÁRIO: percorre os ecrãs para capturas de ecrã. Não faz parte da app.
// ignore_for_file: avoid_print
import 'package:aniversarios/app.dart';
import 'package:aniversarios/core/providers.dart';
import 'package:aniversarios/core/router/app_router.dart';
import 'package:aniversarios/data/local/local_auth_repository.dart';
import 'package:aniversarios/data/models/group_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_PT');
  Intl.defaultLocale = 'pt_PT';
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  final auth = LocalAuthRepository(prefs);
  await auth.init();
  final c = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs), authRepositoryProvider.overrideWithValue(auth)],
  );
  runApp(UncontrolledProviderScope(container: c, child: const VelasApp()));

  Future<void> mark(String name, [int s = 5]) async {
    print('PREVIEW:$name');
    await Future<void>.delayed(Duration(seconds: s));
  }

  await Future<void>.delayed(const Duration(seconds: 4));
  // Segunda conta com o mesmo nome.
  await auth.signUp(name: 'Ana', username: 'ana.silva', email: 'ana2@ex.pt', password: 'password1');
  final ana2 = auth.current!;
  await auth.signOut();
  await auth.signUp(name: 'Ana', username: 'ana', email: 'ana@ex.pt', password: 'password1');
  await Future<void>.delayed(const Duration(seconds: 2));
  final router = c.read(routerProvider);
  router.push('/groups/new');
  await mark('form');
  router.pop();

  final now = DateTime.now();
  final me = auth.current!;
  await c.read(groupsProvider.future);
  await c.read(groupsProvider.notifier).mutate((r) async {
    await r.saveGroup(
      GiftGroup(id: 'g1', createdBy: me.id, title: 'Prenda para a Mãe', celebrantName: 'Helena Duarte', targetAmount: 80, createdAt: now),
      newMembers: [GroupMember(id: 'a', groupId: 'g1', name: me.name, userId: me.id, username: me.username, createdAt: now)],
    );
    final found = await r.findUser('ana.silva');
    print('FOUND:${found?.name} @${found?.username}');
    await r.inviteUser('g1', found!.userId);
  });
  router.push('/groups/g1');
  await mark('admin_pending');
  router.go('/home');

  await auth.signOut();
  await Future<void>.delayed(const Duration(seconds: 1));
  await auth.signIn(identifier: '@ana.silva', password: 'password1');
  await Future<void>.delayed(const Duration(seconds: 2));
  print('LOGGED-AS:${auth.current!.id == ana2.id}');
  router.go('/gifts?tab=groups');
  await mark('invitee_inbox');
  final inv = (await c.read(invitationsProvider.future)).single;
  await c.read(groupsProvider.notifier).mutate((r) => r.respondInvitation(inv.id, accept: true));
  router.push('/groups/g1');
  await mark('accepted');
  print('PREVIEW:done');
}
