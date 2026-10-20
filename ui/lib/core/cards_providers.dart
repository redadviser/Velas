import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/chat_socket.dart';
import '../data/models/card_models.dart';
import 'chat_providers.dart';
import 'providers.dart';

/// Cartões enviados a uma pessoa (para mostrar se foram abertos). Atualiza-se
/// sozinho quando quem recebeu abre ou guarda o cartão.
final sentCardsProvider = FutureProvider.autoDispose.family<List<SentCard>, String>((ref, personId) async {
  final repo = ref.watch(cardsRepositoryProvider);
  if (repo == null || ref.watch(currentUserProvider.select((u) => u?.id)) == null) return const [];
  final sub = ref.watch(chatEventsProvider).listen((e) {
    if (e is CardsChanged) ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);
  return repo.sentTo(personId);
});

/// O meu mural: os cartões de parabéns que recebi (privado).
class WallController extends AsyncNotifier<List<ReceivedCard>> {
  @override
  Future<List<ReceivedCard>> build() async {
    final repo = ref.watch(cardsRepositoryProvider);
    if (repo == null || ref.watch(currentUserProvider.select((u) => u?.id)) == null) return const [];
    final sub = ref.watch(chatEventsProvider).listen((e) {
      if (e is CardsChanged || e is ChatConnected) refresh().catchError((_) {});
    });
    ref.onDispose(sub.cancel);
    return repo.received();
  }

  Future<void> refresh() async {
    final repo = ref.read(cardsRepositoryProvider);
    if (repo == null) return;
    state = AsyncData(await repo.received());
  }

  /// Abri o mural: os novos deixam de estar em destaque.
  Future<void> markSeen() async {
    final cards = state.value ?? const [];
    if (cards.every((c) => c.seen)) return;
    state = AsyncData([
      for (final c in cards)
        ReceivedCard(id: c.id, sender: c.sender, body: c.body, receivedAt: c.receivedAt),
    ]);
    await ref.read(cardsRepositoryProvider)?.markWallSeen();
  }
}

final wallProvider = AsyncNotifierProvider<WallController, List<ReceivedCard>>(WallController.new);

/// Cartões no mural ainda por ver (destaque no Início).
final unseenWallCardsProvider = Provider<List<ReceivedCard>>(
  (ref) => (ref.watch(wallProvider).value ?? const []).where((c) => !c.seen).toList(),
);
