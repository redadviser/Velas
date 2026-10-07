import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api/api_client.dart';
import '../data/api/api_data_repository.dart';
import '../data/api/api_group_repository.dart';
import '../data/local/local_data_repository.dart';
import '../data/local/local_group_repository.dart';
import '../data/models/group_models.dart';
import '../data/models/models.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/data_repository.dart';
import '../data/repositories/group_repository.dart';
import '../services/notification_service.dart';

/// Substituídos em `main()` depois da inicialização assíncrona.
final sharedPrefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError());
final authRepositoryProvider = Provider<AuthRepository>((_) => throw UnimplementedError());

/// Cliente da API, ou `null` no modo local (sem servidor).
final apiClientProvider = Provider<ApiClient?>((_) => null);

final authStateProvider = StreamProvider<UserProfile?>((ref) => ref.watch(authRepositoryProvider).changes);

final currentUserProvider = Provider<UserProfile?>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return ref.watch(authStateProvider).value ?? auth.current;
});

/// Um repositório por sessão: ao mudar de utilizador, os dados anteriores
/// são descartados da memória.
final dataRepositoryProvider = Provider<DataRepository?>((ref) {
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  if (userId == null) return null;
  final api = ref.watch(apiClientProvider);
  final DataRepository repo = api != null
      ? ApiDataRepository(api)
      : LocalDataRepository(ref.watch(sharedPrefsProvider), userId);
  ref.onDispose(repo.dispose);
  return repo;
});

final appDataProvider = StreamProvider<AppData>((ref) async* {
  final repo = ref.watch(dataRepositoryProvider);
  if (repo == null) {
    yield AppData.empty;
    return;
  }
  await repo.load();
  yield* repo.changes;
});

/// Atalho síncrono para os ecrãs: devolve sempre um [AppData].
final dataProvider = Provider<AppData>((ref) => ref.watch(appDataProvider).value ?? AppData.empty);

final groupRepositoryProvider = Provider<GroupRepository?>((ref) {
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  if (userId == null) return null;
  final api = ref.watch(apiClientProvider);
  if (api != null) return ApiGroupRepository(api);
  return LocalGroupRepository(ref.watch(sharedPrefsProvider), () => ref.read(currentUserProvider)!);
});

/// Prendas em grupo. Como são partilhadas com outras pessoas, recarregam
/// do servidor depois de cada alteração e ao puxar para atualizar.
class GroupsController extends AsyncNotifier<List<GiftGroup>> {
  @override
  Future<List<GiftGroup>> build() async {
    final repo = ref.watch(groupRepositoryProvider);
    return repo == null ? const [] : repo.fetchGroups();
  }

  GroupRepository get repo => ref.read(groupRepositoryProvider)!;

  Future<void> refresh() async {
    final repo = ref.read(groupRepositoryProvider);
    if (repo == null) return;
    ref.invalidate(invitationsProvider);
    state = AsyncData(await repo.fetchGroups());
  }

  /// Aplica a alteração de imediato (se dada) e depois sincroniza.
  Future<void> mutate(Future<void> Function(GroupRepository repo) op, {GiftGroup? optimistic}) async {
    final previous = state.value;
    if (optimistic != null && previous != null) {
      final i = previous.indexWhere((g) => g.id == optimistic.id);
      state = AsyncData(i == -1 ? [optimistic, ...previous] : ([...previous]..[i] = optimistic));
    }
    try {
      await op(repo);
    } catch (_) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
    try {
      await refresh();
    } catch (_) {
      // A alteração foi feita; a lista volta a sincronizar na próxima atualização.
    }
  }
}

final groupsProvider = AsyncNotifierProvider<GroupsController, List<GiftGroup>>(GroupsController.new);

/// Convites para grupos que o utilizador recebeu e ainda não respondeu.
final invitationsProvider = FutureProvider<List<InvitationPreview>>((ref) async {
  final repo = ref.watch(groupRepositoryProvider);
  if (repo == null || !repo.supportsInvites) return const [];
  return repo.myInvitations();
});

/// Mantém os lembretes do sistema sincronizados com os dados e preferências.
final notificationSyncProvider = Provider<void>((ref) {
  final user = ref.watch(currentUserProvider);
  final data = ref.watch(appDataProvider).value;
  if (user == null) {
    NotificationService.instance.cancelAll();
  } else if (data != null && data.loaded) {
    NotificationService.instance.reschedule(data.people, user);
  }
});

class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'velas.themeMode';

  @override
  ThemeMode build() {
    final v = ref.watch(sharedPrefsProvider).getString(_key);
    return ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => ThemeMode.system);
  }

  void set(ThemeMode mode) {
    state = mode;
    ref.read(sharedPrefsProvider).setString(_key, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Se o cartão "Importa os teus contactos" do início foi escondido.
class ImportCardController extends Notifier<bool> {
  static const _key = 'velas.importCardDismissed';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_key) ?? false;

  void dismiss() {
    state = true;
    ref.read(sharedPrefsProvider).setBool(_key, true);
  }
}

final importCardDismissedProvider = NotifierProvider<ImportCardController, bool>(ImportCardController.new);
