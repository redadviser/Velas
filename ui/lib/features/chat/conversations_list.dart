import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/constants.dart';
import '../../core/i18n/translations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import '../../data/models/group_models.dart';
import '../../data/models/party_models.dart';
import '../groups/group_widgets.dart';
import '../groups/invite_widgets.dart';
import 'chat_widgets.dart';

/// Uma linha da lista: uma prenda em grupo ou uma festa surpresa.
sealed class PlanItem {
  const PlanItem();

  /// Em curso: a data que vem aí. Concluídos: quando acabou.
  DateTime? get date;
}

class GroupItem extends PlanItem {
  const GroupItem(this.group, this.conversation);

  final GiftGroup group;

  /// `null` no modo local, ou enquanto as conversas carregam.
  final Conversation? conversation;

  @override
  DateTime? get date => group.purchasedAt ?? group.nextBirthday;
}

class PartyItem extends PlanItem {
  const PartyItem(this.party);

  final Party party;

  @override
  DateTime? get date => party.startsAt;
}

/// Em curso (prendas por comprar e festas por acontecer), da mais próxima
/// para a mais longe; ou concluídos, do mais recente para o mais antigo.
List<PlanItem> planItems(
  List<GiftGroup> groups,
  List<Party> parties,
  List<Conversation> conversations, {
  required bool done,
}) {
  final byId = {for (final c in conversations) c.id: c};
  final items = <PlanItem>[
    for (final g in groups)
      if ((g.purchasedAt != null) == done) GroupItem(g, g.conversationId == null ? null : byId[g.conversationId]),
    for (final p in parties)
      if (p.isPast == done) PartyItem(p),
  ];
  return items..sort((a, b) {
    final (x, y) = (a.date, b.date);
    if (x == null || y == null) return x == y ? 0 : (x == null ? 1 : -1);
    return done ? y.compareTo(x) : x.compareTo(y);
  });
}

/// Coisas à espera de mim: mensagens por ler, pedidos de amizade e prendas por pagar.
final conversationsBadgeProvider = Provider<int>((ref) {
  final user = ref.watch(currentUserProvider);
  final toPay = (ref.watch(groupsProvider).value ?? const <GiftGroup>[]).where((g) {
    final me = g.memberFor(user?.id);
    return g.purchasedAt == null && me != null && g.statusOf(me) == ContributionStatus.pending;
  }).length;
  final int unread = ref.watch(unreadTotalProvider);
  final int requests = ref.watch(incomingFriendRequestsProvider);
  return toPay + unread + requests;
});

/// Prendas em grupo e festas surpresa, em curso ou concluídas.
class PlansList extends ConsumerWidget {
  const PlansList({super.key, required this.done});

  final bool done;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatRepositoryProvider) != null;
    final groupsAsync = ref.watch(groupsProvider);
    final parties = ref.watch(partiesProvider).value ?? const <Party>[];
    final conversations = ref.watch(conversationsProvider).value ?? const <Conversation>[];
    final user = ref.watch(currentUserProvider);
    final requests = ref.watch(incomingFriendRequestsProvider);
    final supportsInvites = ref.watch(groupRepositoryProvider)?.supportsInvites ?? false;

    if (groupsAsync.hasError && !groupsAsync.hasValue) {
      return ErrorRetry(error: groupsAsync.error!, onRetry: () => ref.invalidate(groupsProvider));
    }
    final groups = groupsAsync.value;
    if (groups == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    final items = planItems(groups, parties, conversations, done: done);
    final nothingAtAll = groups.isEmpty && parties.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!done) InvitationsInbox(onAccepted: (id) => context.push('/groups/$id')),
        if (!done && requests > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: AppCard(
              color: context.palette.accent,
              onTap: () => context.push('/friends'),
              child: Row(
                children: [
                  Icon(LucideIcons.userPlus, color: context.palette.accentForeground),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.trPlural(Keys.chatFriendRequests, requests),
                      style: context.text.titleSmall?.copyWith(color: context.palette.accentForeground),
                    ),
                  ),
                  Icon(LucideIcons.chevronRight, size: 18, color: context.palette.accentForeground),
                ],
              ),
            ),
          ),
        if (nothingAtAll && !done)
          EmptyState(
            icon: LucideIcons.gift,
            title: context.tr(Keys.chatEmptyTitle),
            message: context.tr(chat ? Keys.chatEmptyMessage : Keys.chatEmptyMessageLocal),
            action: Column(
              children: [
                FilledButton.icon(
                  onPressed: () => context.push('/groups/new'),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: Text(context.tr(Keys.chatEmptyCreateGroup)),
                  style: FilledButton.styleFrom(minimumSize: const Size(240, 52)),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.push('/parties/new'),
                  child: Text(context.tr('Organizar uma festa surpresa')),
                ),
                if (supportsInvites)
                  TextButton(
                    onPressed: () => showJoinCodeSheet(context, ref),
                    child: Text(context.tr(Keys.chatEmptyHaveCode)),
                  ),
                if (chat)
                  TextButton(
                    onPressed: () => context.push('/friends'),
                    child: Text(context.tr(Keys.chatEmptyAddFriends)),
                  ),
              ],
            ),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Text(
              done
                  ? context.tr('Ainda não há prendas compradas nem festas passadas.')
                  : context.tr('Nada em curso de momento.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.mutedForeground),
            ),
          )
        else
          for (final item in items)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: switch (item) {
                GroupItem(:final group, :final conversation) => GiftPlanCard(
                  group: group,
                  conversation: conversation,
                  myId: user?.id,
                ),
                PartyItem(:final party) => PartyPlanCard(party: party),
              },
            ),
      ],
    );
  }
}

/// Moldura comum: ícone à esquerda, texto ao meio, contador e seta à direita.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.eyebrow,
    required this.eyebrowColor,
    required this.title,
    required this.onTap,
    this.eyebrowIcon,
    this.children = const [],
    this.unread = 0,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final IconData? eyebrowIcon;
  final String eyebrow;
  final Color eyebrowColor;
  final String title;
  final List<Widget> children;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Row(
        children: [
          IconBadge(icon: icon, size: 56, background: iconBackground, foreground: iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (eyebrowIcon != null) ...[
                      Icon(eyebrowIcon, size: 13, color: eyebrowColor),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        eyebrow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelMedium?.copyWith(color: eyebrowColor, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTheme.display(context, size: 17)),
                ...children,
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (unread > 0) ...[CountBadge(count: unread), const SizedBox(width: 4)],
          Icon(LucideIcons.chevronRight, size: 20, color: context.colors.onSurface),
        ],
      ),
    );
  }
}

/// Prenda em grupo: o que se oferece, quanto já se juntou e quem falta pagar.
class GiftPlanCard extends StatelessWidget {
  const GiftPlanCard({super.key, required this.group, required this.conversation, required this.myId});

  final GiftGroup group;
  final Conversation? conversation;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final muted = context.palette.mutedForeground;
    final me = g.memberFor(myId);
    final bought = g.purchasedAt != null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ratio = g.targetAmount <= 0 ? 0.0 : (g.confirmedAmount / g.targetAmount).clamp(0.0, 1.0);
    final next = g.nextBirthday;
    final subtitle = g.giftDescription.trim().isNotEmpty
        ? g.giftDescription.trim()
        : next == null
        ? context.tr('Para {name}', {'name': g.celebrantName})
        : context.tr('Para {name} · {date}', {'name': g.celebrantName, 'date': Fmt.dayMonth(next)});
    final mustPay = !bought && me != null && g.statusOf(me) == ContributionStatus.pending;

    return _PlanCard(
      icon: bought ? LucideIcons.packageCheck : LucideIcons.gift,
      iconBackground: dark ? context.palette.muted : AppColors.tones[3].$1,
      iconColor: dark ? context.colors.onSurface : AppColors.tones[3].$2,
      eyebrowIcon: bought ? LucideIcons.check : LucideIcons.eyeOff,
      eyebrow: bought ? context.tr('Comprada') : context.tr('Em segredo'),
      eyebrowColor: bought ? context.palette.success : context.colors.primary,
      title: g.title,
      unread: conversation?.unreadCount ?? 0,
      onTap: () => context.push('/groups/${g.id}'),
      children: [
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodySmall?.copyWith(color: muted),
        ),
        if (!bought && g.targetAmount > 0) ...[
          const SizedBox(height: 10),
          SoftProgress(value: ratio, semanticsLabel: context.tr('Valor juntado')),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              [
                context.tr('{confirmed} de {target}', {
                  'confirmed': Fmt.money(g.confirmedAmount),
                  'target': Fmt.money(g.targetAmount),
                }),
                if (!bought && g.pendingCount > 0)
                  g.pendingCount == 1
                      ? context.tr('falta 1 pagamento')
                      : context.tr('faltam {count} pagamentos', {'count': g.pendingCount}),
              ].join(' · '),
              style: context.text.labelSmall?.copyWith(color: muted),
            ),
            if (mustPay)
              Pill(
                label: context.tr('Pagar {amount}', {'amount': Fmt.money(g.shareOf(me))}),
                background: context.colors.primary,
                foreground: context.colors.onPrimary,
                dense: true,
              ),
          ],
        ),
      ],
    );
  }
}

/// Festa surpresa: quando é e quantos convidados.
class PartyPlanCard extends StatelessWidget {
  const PartyPlanCard({super.key, required this.party});

  final Party party;

  @override
  Widget build(BuildContext context) {
    final p = party;
    final n = p.guests.length;
    return _PlanCard(
      icon: LucideIcons.partyPopper,
      iconBackground: context.palette.violetSoft,
      iconColor: context.colors.secondary,
      eyebrow: context.tr('Surpresa para {name}', {'name': p.celebrantName}),
      eyebrowColor: context.colors.secondary,
      title: p.title,
      onTap: () => context.push('/parties/${p.id}'),
      children: [
        const SizedBox(height: 2),
        Text(
          [
            p.startsAt == null ? context.tr('Data por marcar') : Fmt.dayMonth(p.startsAt!),
            n == 1 ? context.tr('1 convidado') : context.tr('{count} convidados', {'count': n}),
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
        ),
      ],
    );
  }
}
