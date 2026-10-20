import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/cards_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/models/card_models.dart';
import '../chat/chat_widgets.dart';
import '../chat/conversations_list.dart';

/// O mural: todas as mensagens de parabéns que a pessoa recebeu pela
/// Birthdayly (cartões guardados a partir de um link ou publicados aqui por
/// amigos), por ano. É privado: só a própria pessoa o vê.
class WallScreen extends ConsumerStatefulWidget {
  const WallScreen({super.key});

  @override
  ConsumerState<WallScreen> createState() => _WallScreenState();
}

class _WallScreenState extends ConsumerState<WallScreen> {
  /// Os que eram novos ao abrir: ficam em destaque enquanto o ecrã estiver aberto.
  Set<String> _fresh = const {};

  @override
  void initState() {
    super.initState();
    ref.read(wallProvider.future).then((cards) {
      if (!mounted) return;
      setState(() => _fresh = {for (final c in cards) if (!c.seen) c.id});
      ref.read(wallProvider.notifier).markSeen().catchError((_) {});
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final wall = ref.watch(wallProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('O teu mural')),
      body: wall.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(wallProvider)),
        data: (cards) => RefreshIndicator(
          onRefresh: () => ref.read(wallProvider.notifier).refresh(),
          child: cards.isEmpty
              ? ListView(
                  children: const [
                    EmptyState(
                      icon: LucideIcons.partyPopper,
                      title: 'Ainda sem parabéns por aqui',
                      message:
                          'Quando alguém te mandar um cartão de parabéns pela Birthdayly, fica guardado neste mural. '
                          'Só tu o vês.',
                    ),
                  ],
                )
              : _WallList(cards: cards, fresh: _fresh),
        ),
      ),
    );
  }
}

class _WallList extends StatelessWidget {
  const _WallList({required this.cards, required this.fresh});

  final List<ReceivedCard> cards;
  final Set<String> fresh;

  @override
  Widget build(BuildContext context) {
    final people = {for (final c in cards) c.sender.userId}.length;
    final muted = context.palette.mutedForeground;
    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        child: Text(
          '${cards.length} ${cards.length == 1 ? 'mensagem' : 'mensagens'} de parabéns'
          ' de $people ${people == 1 ? 'pessoa' : 'pessoas'}',
          style: context.text.bodyMedium?.copyWith(color: muted),
        ),
      ),
    ];
    int? year;
    for (final c in cards) {
      if (c.receivedAt.year != year) {
        year = c.receivedAt.year;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
            child: Text('$year', style: AppTheme.display(context, size: 22)),
          ),
        );
      }
      rows.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: _WallCard(card: c, fresh: fresh.contains(c.id))));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: rows);
  }
}

class _WallCard extends ConsumerWidget {
  const _WallCard({required this.card, required this.fresh});

  final ReceivedCard card;
  final bool fresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = context.palette.mutedForeground;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              UserAvatar(user: card.sender, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.sender.name, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                    Text(Fmt.dayMonth(card.receivedAt), style: context.text.bodySmall?.copyWith(color: muted)),
                  ],
                ),
              ),
              if (fresh)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Pill(
                    label: 'Nova',
                    dense: true,
                    background: AppColors.brandGradient.colors.first,
                    foreground: Colors.white,
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 8, 4),
            child: Text(
              card.body,
              style: AppTheme.display(context, size: 17).copyWith(fontWeight: FontWeight.w400, height: 1.5),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => openDirectChat(context, ref, card.sender.userId),
              icon: const Icon(LucideIcons.messageCircle, size: 16),
              label: Text('Agradecer a ${card.sender.firstName}'),
            ),
          ),
        ],
      ),
    );
  }
}

/// No Início, quando chegam parabéns novos ao mural.
class WallBanner extends ConsumerWidget {
  const WallBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unseen = ref.watch(unseenWallCardsProvider);
    if (unseen.isEmpty) return const SizedBox.shrink();
    final senders = {for (final c in unseen) c.sender.userId}.length;
    final title = senders == 1
        ? '${unseen.first.sender.firstName} deixou-te ${unseen.length == 1 ? 'uma mensagem' : '${unseen.length} mensagens'} de parabéns'
        : 'Tens ${unseen.length} mensagens de parabéns novas';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(20)),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => context.push('/wall'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  const Icon(LucideIcons.partyPopper, color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$title 🎉',
                          style: context.text.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Abre o teu mural para as leres',
                          style: context.text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                        ),
                      ],
                    ),
                  ),
                  const Icon(LucideIcons.chevronRight, color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
