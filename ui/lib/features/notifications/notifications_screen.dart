import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/models/group_models.dart';
import '../../data/models/party_models.dart';
import '../../services/reminder_copy.dart';
import '../people/birthday_request.dart';

/// Uma coisa por tratar: o texto e para onde leva.
typedef _Action = ({IconData icon, int tone, String title, String subtitle, String route});

/// O que precisa de ti agora (o Início mostra um ponto no sino se houver).
List<_Action> _actions(WidgetRef ref) {
  final data = ref.watch(dataProvider);
  final me = ref.watch(currentUserProvider)?.id;
  final out = <_Action>[];
  for (final p in data.upcoming.where((p) => p.isToday)) {
    out.add((
      icon: LucideIcons.cake,
      tone: 0,
      title: 'Hoje é o aniversário de ${p.firstName}',
      subtitle: data.messageFor(p.id) == null ? 'Escreve-lhe os parabéns' : 'A tua mensagem está pronta',
      route: '/person/${p.id}/message',
    ));
  }
  for (final d in data.specialDates.where((d) => d.daysUntil() == 0)) {
    out.add((
      icon: LucideIcons.heart,
      tone: 1,
      title: 'Hoje: ${d.title}',
      subtitle: 'Um dia para assinalar',
      route: '/special',
    ));
  }
  for (final g in (ref.watch(groupsProvider).value ?? const <GiftGroup>[]).where((g) => g.purchasedAt == null)) {
    final m = g.memberFor(me);
    if (m == null) continue;
    if (g.isBuyer(m) && g.awaitingConfirmationCount > 0) {
      final n = g.awaitingConfirmationCount;
      out.add((
        icon: LucideIcons.badgeCheck,
        tone: 2,
        title: n == 1 ? '1 pagamento para confirmares' : '$n pagamentos para confirmares',
        subtitle: g.title,
        route: '/groups/${g.id}',
      ));
    } else if (!g.isBuyer(m) && g.statusOf(m) == ContributionStatus.pending) {
      out.add((
        icon: LucideIcons.wallet,
        tone: 3,
        title: 'Falta pagares ${Fmt.money(g.shareOf(m))}',
        subtitle: g.title,
        route: '/groups/${g.id}',
      ));
    }
  }
  for (final i in ref.watch(invitationsProvider).value ?? const []) {
    out.add((
      icon: LucideIcons.mailOpen,
      tone: 1,
      title: '${i.inviterName} convidou-te',
      subtitle: i.title,
      route: '/gifts?tab=chats',
    ));
  }
  for (final p in ref.watch(partiesProvider).value ?? const <Party>[]) {
    if (!p.isPast && !p.isHost(me) && p.guestFor(me)?.rsvp == Rsvp.pending) {
      out.add((icon: LucideIcons.partyPopper, tone: 1, title: 'Vais à festa de ${p.celebrantName}?', subtitle: p.title, route: '/parties/${p.id}'));
    }
  }
  final requests = ref.watch(incomingFriendRequestsProvider);
  if (requests > 0) {
    out.add((
      icon: LucideIcons.userPlus,
      tone: 4,
      title: requests == 1 ? '1 pedido de amizade' : '$requests pedidos de amizade',
      subtitle: 'Aceita para trocarem mensagens e prendas',
      route: '/friends',
    ));
  }
  final answers = ref.watch(birthdayRequestProvider).value?.pending ?? 0;
  if (answers > 0) {
    out.add((
      icon: LucideIcons.inbox,
      tone: 2,
      title: answers == 1 ? '1 data recebida pelo link' : '$answers datas recebidas pelo link',
      subtitle: 'Confirma antes de as juntar',
      route: '/people/requests',
    ));
  }
  return out;
}

/// Número de coisas por tratar (para o ponto no sino do Início).
int pendingActionsCount(WidgetRef ref) => _actions(ref).length;

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final data = ref.watch(dataProvider);
    final actions = _actions(ref);
    final planned = user == null || !user.notificationsEnabled
        ? const <PlannedReminder>[]
        : ReminderCopy.plan(data, user, DateTime.now()).take(4).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Notificações')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Text('PARA TRATAR', style: AppTheme.eyebrow(context)),
          const SizedBox(height: 10),
          if (actions.isEmpty)
            AppCard(
              raised: false,
              child: Row(
                children: [
                  IconBadge(
                    icon: LucideIcons.circleCheck,
                    background: context.palette.success.withValues(alpha: 0.14),
                    foreground: context.palette.success,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Está tudo em dia. Avisamos-te quando houver novidades.',
                      style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground),
                    ),
                  ),
                ],
              ),
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, a) in actions.indexed) ...[
                    if (i > 0) const Divider(indent: 70),
                    ListTile(
                      onTap: () => context.push(a.route),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      leading: IconBadge(
                        icon: a.icon,
                        background: isDark ? context.palette.muted : AppColors.tones[a.tone].$1,
                        foreground: isDark
                            ? Color.lerp(AppColors.swatches[a.tone], Colors.white, 0.45)
                            : AppColors.tones[a.tone].$2,
                      ),
                      title: Text(a.title, style: context.text.titleSmall),
                      subtitle: Text(a.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Icon(LucideIcons.chevronRight, size: 18, color: context.palette.mutedForeground),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text('PRÓXIMOS AVISOS', style: AppTheme.eyebrow(context))),
              TextButton(onPressed: () => context.go('/profile'), child: const Text('Quando avisar')),
            ],
          ),
          const SizedBox(height: 4),
          if (user != null && !user.notificationsEnabled)
            Text(
              'Tens as notificações desligadas. Liga-as no perfil para não falhares nenhum dia.',
              style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground),
            )
          else if (planned.isEmpty)
            Text(
              'Ainda não há avisos marcados. Adiciona aniversários ou datas especiais.',
              style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground),
            )
          else
            for (final p in planned) ...[
              _Preview(planned: p, reminder: ReminderCopy.copyFor(p, data)),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

/// Um aviso como aparece no telemóvel.
class _Preview extends StatelessWidget {
  const _Preview({required this.planned, required this.reminder});

  final PlannedReminder planned;
  final Reminder reminder;

  @override
  Widget build(BuildContext context) {
    final w = planned.when;
    final days = BirthdayUtils.daysUntil(w.day, w.month);
    final time = '${w.hour.toString().padLeft(2, '0')}:${w.minute.toString().padLeft(2, '0')}';
    final when = switch (days) {
      0 => 'hoje às $time',
      1 => 'amanhã às $time',
      _ => '${Fmt.dayMonth(w)} às $time',
    };
    return AppCard(
      raised: false,
      color: context.palette.muted,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandMark(size: 34, showName: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Birthdayly ',
                        style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: when,
                        style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(reminder.title, style: context.text.titleSmall),
                Text(reminder.body, style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
