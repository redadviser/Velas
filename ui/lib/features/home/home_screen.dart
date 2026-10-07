import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/data_gate.dart';
import '../../data/models/group_models.dart';
import '../../data/models/models.dart';
import '../people/import_contacts_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final today = BirthdayUtils.today();

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-home',
        tooltip: 'Adicionar aniversário',
        onPressed: () => context.push('/person/new'),
        child: const Icon(LucideIcons.plus),
      ),
      body: SafeArea(
        bottom: false,
        child: DataGate(
          builder: (context, data) {
            final upcoming = data.upcoming;
            final todays = upcoming.where((p) => p.isToday).toList();
            final next = upcoming.where((p) => !p.isToday).firstOrNull;
            final soon = upcoming.where((p) => !p.isToday && p != next && p.daysUntil() <= 60).take(5).toList();

            return RefreshIndicator(
              onRefresh: () => refreshData(ref),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  _Header(name: user?.firstName ?? '', date: today, user: user),
                  const _GroupsBanner(),
                  if (data.people.isEmpty)
                    EmptyState(
                      icon: LucideIcons.cake,
                      title: 'Começa pelos teus contactos',
                      message:
                          'Importa os aniversários que já tens no telemóvel ou no Google, '
                          'ou adiciona alguém especial. Nós tratamos de te lembrar a tempo.',
                      action: Column(
                        children: [
                          FilledButton.icon(
                            onPressed: () => context.push('/import'),
                            icon: const Icon(LucideIcons.contactRound, size: 18),
                            label: const Text('Importar contactos'),
                            style: FilledButton.styleFrom(minimumSize: const Size(260, 52)),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => context.push('/person/new'),
                            icon: const Icon(LucideIcons.userPlus, size: 18),
                            label: const Text('Adicionar manualmente'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(260, 52)),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    if (!ref.watch(importCardDismissedProvider))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: ImportContactsCard(
                          onDismiss: () => ref.read(importCardDismissedProvider.notifier).dismiss(),
                        ),
                      ),
                    if (todays.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: _TodayCard(people: todays, data: data),
                      ),
                    if (next != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: _NextUpCard(person: next, data: data),
                      ),
                    const SectionTitle('Os próximos 7 dias'),
                    _WeekStrip(data: data, start: today),
                    const SizedBox(height: 8),
                    _Stats(data: data),
                    if (soon.isNotEmpty) ...[
                      SectionTitle('Em breve', action: 'Ver agenda', onAction: () => context.go('/agenda')),
                      for (final p in soon)
                        PersonTile(person: p, data: data, onTap: () => context.push('/person/${p.id}')),
                    ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.date, required this.user});

  final String name;
  final DateTime date;
  final UserProfile? user;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Bom dia'
        : hour < 20
        ? 'Boa tarde'
        : 'Boa noite';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Fmt.weekdayDayMonth(date),
                  style: context.text.labelMedium?.copyWith(color: context.palette.mutedForeground),
                ),
                const SizedBox(height: 2),
                Text(name.isEmpty ? greeting : '$greeting, $name', style: AppTheme.display(context, size: 28)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Importar contactos',
            onPressed: () => context.push('/import'),
            icon: const Icon(LucideIcons.contactRound),
          ),
          IconButton(
            tooltip: 'Perfil',
            onPressed: () => context.push('/profile'),
            icon: CircleAvatar(
              radius: 20,
              backgroundColor: context.palette.accent,
              child: Text(
                (user?.name.isNotEmpty ?? false) ? user!.name[0].toUpperCase() : '?',
                style: TextStyle(color: context.palette.accentForeground, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Destaque festivo: é o único sítio onde o gradiente da marca é usado em
/// grande, para que o momento seja especial.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.people, required this.data});

  final List<Person> people;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(24)),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.partyPopper, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                people.length == 1 ? 'HOJE É DIA DE FESTA' : 'HOJE HÁ ${people.length} ANIVERSÁRIOS',
                style: context.text.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          for (final p in people) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: PersonAvatar(person: p, color: personColor(p, data), size: 52),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: AppTheme.display(context, size: 22, color: Colors.white)),
                      Text(
                        [
                          if (p.turningAge != null) 'Faz ${p.turningAge} anos',
                          if (p.relation.isNotEmpty) p.relation,
                        ].join(' · '),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push('/person/${p.id}/message'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.accentForeground,
                      minimumSize: const Size.fromHeight(44),
                    ),
                    icon: const Icon(LucideIcons.messageSquareHeart, size: 18),
                    label: Text(data.messageFor(p.id) == null ? 'Escrever parabéns' : 'Enviar mensagem'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  tooltip: 'Ver detalhes',
                  onPressed: () => context.push('/person/${p.id}'),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                    fixedSize: const Size(44, 44),
                  ),
                  icon: const Icon(LucideIcons.arrowRight, size: 20),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Cartão do próximo aniversário com contagem decrescente e o estado de
/// preparação (mensagem e presente).
class _NextUpCard extends StatelessWidget {
  const _NextUpCard({required this.person, required this.data});

  final Person person;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    final days = person.daysUntil();
    final date = person.nextBirthday();
    final hasMessage = data.messageFor(person.id) != null;
    final gifts = data.giftsFor(person.id);
    final giftReady = gifts.any((g) => g.purchased);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.push('/person/${person.id}'),
        child: Ink(
          decoration: BoxDecoration(
            gradient: context.palette.softGradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.palette.border),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PRÓXIMO ANIVERSÁRIO',
                style: context.text.labelSmall?.copyWith(
                  color: context.palette.accentForeground,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$days', style: AppTheme.display(context, size: 56).copyWith(height: 1)),
                      Text(
                        days == 1 ? 'dia' : 'dias',
                        style: context.text.labelLarge?.copyWith(color: context.palette.mutedForeground),
                      ),
                    ],
                  ),
                  Container(
                    width: 1,
                    height: 64,
                    margin: const EdgeInsets.symmetric(horizontal: 18),
                    color: context.palette.border,
                  ),
                  PersonAvatar(person: person, color: personColor(person, data), size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (person.turningAge != null) 'Faz ${person.turningAge}',
                            '${Fmt.weekdayShort(date)}, ${Fmt.dayMonth(date)}',
                          ].join(' · '),
                          style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ReadyChip(
                    ready: hasMessage,
                    icon: LucideIcons.messageSquareHeart,
                    readyLabel: 'Mensagem pronta',
                    pendingLabel: 'Escrever mensagem',
                    onTap: () => context.push('/person/${person.id}/message'),
                  ),
                  _ReadyChip(
                    ready: giftReady,
                    icon: LucideIcons.gift,
                    readyLabel: 'Presente comprado',
                    pendingLabel: gifts.isEmpty ? 'Pensar num presente' : '${gifts.length} ideias de presente',
                    onTap: () => context.push('/person/${person.id}'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadyChip extends StatelessWidget {
  const _ReadyChip({
    required this.ready,
    required this.icon,
    required this.readyLabel,
    required this.pendingLabel,
    required this.onTap,
  });

  final bool ready;
  final IconData icon;
  final String readyLabel;
  final String pendingLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final success = context.palette.success;
    final fg = ready ? success : context.colors.onSurface;
    return Material(
      color: ready ? success.withValues(alpha: 0.12) : context.palette.card,
      shape: StadiumBorder(side: BorderSide(color: ready ? Colors.transparent : context.palette.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ready ? LucideIcons.circleCheck : icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(
                ready ? readyLabel : pendingLabel,
                style: context.text.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.data, required this.start});

  final AppData data;
  final DateTime start;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Builder(
                builder: (context) {
                  final day = BirthdayUtils.addDays(start, i);
                  final people = data.people.where((p) => p.daysUntil() == i).toList();
                  final isToday = i == 0;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isToday ? context.colors.onSurface : context.palette.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isToday ? Colors.transparent : context.palette.border),
                    ),
                    child: Column(
                      children: [
                        Text(
                          Fmt.weekdayShort(day).substring(0, 3),
                          style: context.text.labelSmall?.copyWith(
                            color: isToday
                                ? context.colors.surface.withValues(alpha: 0.7)
                                : context.palette.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${day.day}',
                          style: AppTheme.display(context, size: 18, color: isToday ? context.colors.surface : null),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 6,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final p in people.take(3))
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(color: personColor(p, data), shape: BoxShape.circle),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.data});

  final AppData data;

  @override
  Widget build(BuildContext context) {
    final today = BirthdayUtils.today();
    final thisMonth = data.people.where((p) => p.month == today.month).length;
    final next30 = data.people.where((p) => p.daysUntil() <= 30).length;
    final toBuy = data.gifts.where((g) => !g.purchased).length;

    Widget tile(String value, String label, IconData icon, VoidCallback onTap) => Expanded(
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: context.colors.primary),
            const SizedBox(height: 10),
            Text(value, style: AppTheme.display(context, size: 24)),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground, fontSize: 12),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          tile(
            '$thisMonth',
            'Em ${Fmt.monthName(today.month).toLowerCase()}',
            LucideIcons.calendarHeart,
            () => context.go('/agenda'),
          ),
          const SizedBox(width: 10),
          tile('$next30', 'Em 30 dias', LucideIcons.bellRing, () => context.go('/agenda')),
          const SizedBox(width: 10),
          tile('$toBuy', 'Por comprar', LucideIcons.shoppingBag, () => context.go('/gifts')),
        ],
      ),
    );
  }
}

/// Lembra pagamentos de prendas em grupo: o que tens de pagar e o que tens
/// de confirmar como comprador.
class _GroupsBanner extends ConsumerWidget {
  const _GroupsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final groups = (ref.watch(groupsProvider).value ?? const <GiftGroup>[]).where((g) => g.purchasedAt == null);
    final toPay = <(GiftGroup, double)>[];
    var toConfirm = <GiftGroup>[];
    for (final g in groups) {
      final me = g.memberFor(user?.id);
      if (me == null) continue;
      if (g.isBuyer(me)) {
        if (g.awaitingConfirmationCount > 0) toConfirm = [...toConfirm, g];
      } else if (g.statusOf(me) == ContributionStatus.pending) {
        toPay.add((g, g.shareOf(me)));
      }
    }
    final invitations = ref.watch(invitationsProvider).value ?? const [];
    if (toPay.isEmpty && toConfirm.isEmpty && invitations.isEmpty) return const SizedBox.shrink();

    final total = toPay.fold<double>(0, (a, e) => a + e.$2);
    final confirmCount = toConfirm.fold<int>(0, (a, g) => a + g.awaitingConfirmationCount);
    final single = invitations.isEmpty && toPay.length + toConfirm.length == 1
        ? (toPay.isNotEmpty ? toPay.first.$1 : toConfirm.first)
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: AppCard(
        color: context.palette.accent,
        onTap: () => single != null ? context.push('/groups/${single.id}') : context.go('/gifts?tab=groups'),
        child: Row(
          children: [
            Icon(LucideIcons.usersRound, color: context.palette.accentForeground, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (invitations.isNotEmpty)
                    Text(
                      invitations.length == 1
                          ? '${invitations.first.inviterName} convidou-te para "${invitations.first.title}"'
                          : 'Tens ${invitations.length} convites para prendas em grupo',
                      style: context.text.titleSmall?.copyWith(color: context.palette.accentForeground),
                    ),
                  if (toPay.isNotEmpty)
                    Text(
                      toPay.length == 1
                          ? 'Falta pagares ${Fmt.money(total)} · ${toPay.first.$1.title}'
                          : 'Tens ${toPay.length} prendas em grupo por pagar · ${Fmt.money(total)}',
                      style: context.text.titleSmall?.copyWith(color: context.palette.accentForeground),
                    ),
                  if (confirmCount > 0)
                    Text(
                      '$confirmCount pagamento${confirmCount == 1 ? '' : 's'} para confirmares que recebeste',
                      style: (toPay.isEmpty ? context.text.titleSmall : context.text.bodySmall)?.copyWith(
                        color: context.palette.accentForeground,
                      ),
                    ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: context.palette.accentForeground, size: 18),
          ],
        ),
      ),
    );
  }
}
