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
import '../cards/wall_screen.dart';
import '../notifications/notifications_screen.dart';
import '../special/special_dates_screen.dart';
import '../parties/party_widgets.dart';
import 'home_inbox.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final today = BirthdayUtils.today();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: DataGate(
          builder: (context, data) {
            final upcoming = data.upcoming;
            final todays = upcoming.where((p) => p.isToday).toList();
            final next = upcoming.where((p) => !p.isToday).firstOrNull;
            final thisMonth = data.people.where((p) => p.month == today.month).length;

            return RefreshIndicator(
              onRefresh: () => refreshData(ref),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 110),
                children: [
                  _Header(name: user?.firstName ?? '', date: today, thisMonth: thisMonth),
                  const WallBanner(),
                  const HomeInbox(),
                  const _GroupsBanner(),
                  if (data.people.isEmpty)
                    EmptyState(
                      icon: LucideIcons.cake,
                      title: 'Começa por quem importa',
                      message: 'Adiciona os aniversários da família e dos amigos. Nós tratamos de te lembrar a tempo.',
                      action: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton.icon(
                            onPressed: () => context.push('/people/import'),
                            icon: const Icon(LucideIcons.contactRound, size: 18),
                            label: const Text('Adicionar dos contactos'),
                            style: FilledButton.styleFrom(minimumSize: const Size(260, 52)),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => context.push('/person/new'),
                            icon: const Icon(LucideIcons.userPlus, size: 18),
                            label: const Text('Adicionar à mão'),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    for (final p in todays)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: _HeroCard(person: p, data: data),
                      ),
                    if (next != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: _HeroCard(person: next, data: data),
                      ),
                    _Upcoming(data: data, exclude: {...todays.map((p) => p.id), ?next?.id}),
                    SectionTitle(
                      'Datas especiais',
                      action: data.specialDates.isEmpty ? null : 'Gerir',
                      onAction: () => context.push('/special'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: data.specialDates.isEmpty
                          ? DashedButton(
                              icon: LucideIcons.heart,
                              label: 'Guardar um casamento, namoro ou outra data',
                              onTap: () => showSpecialDateEditor(context, ref),
                            )
                          : Column(
                              children: [
                                for (final d in data.upcomingSpecialDates.take(2)) ...[
                                  SpecialDateTile(date: d, data: data, onTap: () => context.push('/special')),
                                  const SizedBox(height: 10),
                                ],
                              ],
                            ),
                    ),
                    const _ActiveGroups(),
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
  const _Header({required this.name, required this.date, required this.thisMonth});

  final String name;
  final DateTime date;
  final int thisMonth;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Bom dia'
        : hour < 20
        ? 'Boa tarde'
        : 'Boa noite';
    final line = switch (thisMonth) {
      0 => 'Um mês calmo. Aproveita para pôr a agenda em dia.',
      1 => 'Este mês há um aniversário para celebrar.',
      _ => 'Este mês há $thisMonth aniversários para celebrar.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Fmt.weekdayDayMonth(date).toUpperCase(), style: AppTheme.eyebrow(context)),
                const SizedBox(height: 4),
                Text(name.isEmpty ? '$greeting!' : '$greeting, $name!', style: AppTheme.display(context, size: 29)),
                const SizedBox(height: 4),
                Text(line, style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const _Bell(),
        ],
      ),
    );
  }
}

/// Sino com um ponto quando há coisas por tratar.
class _Bell extends ConsumerWidget {
  const _Bell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = pendingActionsCount(ref);
    return Semantics(
      button: true,
      label: pending == 0 ? 'Notificações' : 'Notificações, $pending por tratar',
      excludeSemantics: true,
      child: Material(
        color: context.palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.palette.border),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onTap: () => context.push('/notifications'),
          child: SizedBox.square(
            dimension: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(LucideIcons.bell, size: 22, color: context.colors.onSurface),
                if (pending > 0)
                  Positioned(
                    right: 11,
                    top: 10,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: context.colors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.palette.card, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Destaque do próximo aniversário (ou de quem faz anos hoje): o único sítio
/// onde o gradiente da marca aparece em grande.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.person, required this.data});

  final Person person;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    final days = person.daysUntil();
    final isToday = days == 0;
    final date = person.nextBirthday();
    final hasMessage = data.messageFor(person.id) != null;
    final gifts = data.giftsFor(person.id);
    final giftReady = gifts.any((g) => g.purchased);
    const white = Colors.white;
    final soft = white.withValues(alpha: 0.88);

    Widget orb(double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: white.withValues(alpha: 0.08)),
    );

    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: white),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelLarge?.copyWith(color: white, fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(29),
        boxShadow: [
          BoxShadow(color: context.colors.primary.withValues(alpha: 0.25), blurRadius: 34, offset: const Offset(0, 16)),
        ],
      ),
      child: Material(
        borderRadius: BorderRadius.circular(29),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(gradient: context.palette.brand),
          child: InkWell(
            onTap: () => context.push('/person/${person.id}'),
            child: Stack(
              children: [
                Positioned(right: -40, top: -55, child: orb(160)),
                Positioned(left: -60, bottom: -40, child: orb(120)),
                Positioned(
                  right: 20,
                  top: 46,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: white.withValues(alpha: 0.7), width: 5),
                      boxShadow: const [BoxShadow(color: Color(0x38501428), blurRadius: 25, offset: Offset(0, 12))],
                    ),
                    child: PersonAvatar(person: person, color: personColor(person, data), size: 100),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 202),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 22, 140, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: white.withValues(alpha: 0.25)),
                              ),
                              child: Text(
                                isToday ? 'HOJE É DIA DE FESTA' : 'PRÓXIMO ANIVERSÁRIO',
                                style: AppTheme.eyebrow(context, color: white).copyWith(fontSize: 10),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              person.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.display(context, size: 26, color: white).copyWith(height: 1.05),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              [
                                if (person.turningAge != null)
                                  isToday ? 'Faz ${person.turningAge} anos hoje' : 'Faz ${person.turningAge} anos',
                                if (!isToday) Fmt.dayMonth(date),
                                if (isToday && person.relation.isNotEmpty) person.relation,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodySmall?.copyWith(color: soft, fontSize: 13),
                            ),
                            const SizedBox(height: 12),
                            if (isToday)
                              const Icon(LucideIcons.partyPopper, color: white, size: 36)
                            else ...[
                              Text(
                                '$days',
                                style: AppTheme.display(context, size: 40, color: white).copyWith(height: 1),
                              ),
                              Text(days == 1 ? 'dia' : 'dias', style: context.text.labelSmall?.copyWith(color: soft)),
                            ],
                          ],
                        ),
                      ),
                    ),
                    ColoredBox(
                      color: const Color(0x2E76122F),
                      child: Row(
                        children: [
                          action(
                            hasMessage ? LucideIcons.circleCheck : LucideIcons.messageSquareHeart,
                            hasMessage ? 'Mensagem pronta' : 'Enviar parabéns',
                            () => context.push('/person/${person.id}/message'),
                          ),
                          Container(width: 1, height: 28, color: white.withValues(alpha: 0.2)),
                          action(
                            giftReady ? LucideIcons.circleCheck : LucideIcons.gift,
                            giftReady
                                ? 'Prenda comprada'
                                : gifts.isEmpty
                                ? 'Ideias de prenda'
                                : '${gifts.length} ${gifts.length == 1 ? 'ideia' : 'ideias'}',
                            () => context.push('/person/${person.id}'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Os próximos aniversários (os 8 primeiros), com filtro por categoria e agrupados por
/// "esta semana", "este mês" e "mais tarde".
class _Upcoming extends StatefulWidget {
  const _Upcoming({required this.data, required this.exclude});

  final AppData data;
  final Set<String> exclude;

  @override
  State<_Upcoming> createState() => _UpcomingState();
}

class _UpcomingState extends State<_Upcoming> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final cats = data.categories;
    final today = BirthdayUtils.today();
    final list = data.upcoming
        .where((p) => !widget.exclude.contains(p.id))
        .where((p) => _category == null || p.categoryId == _category)
        .take(8)
        .toList();
    if (list.isEmpty && _category == null) return const SizedBox.shrink();

    final groups = <String, List<Person>>{};
    for (final p in list) {
      final d = p.daysUntil();
      final key = d <= 7
          ? 'ESTA SEMANA'
          : p.nextBirthday().month == today.month
          ? 'ESTE MÊS'
          : 'MAIS TARDE';
      (groups[key] ??= []).add(p);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle('Próximos aniversários', action: 'Ver todos', onAction: () => context.go('/people')),
        if (cats.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final (id, name) in [(null, 'Todos'), for (final c in cats) (c.id, c.name)])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(name),
                      selected: _category == id,
                      onSelected: (_) => setState(() => _category = id),
                    ),
                  ),
              ],
            ),
          ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              'Ainda não há ninguém nesta categoria.',
              style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground),
            ),
          ),
        for (final e in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 20, 2),
            child: Text(e.key, style: AppTheme.eyebrow(context)),
          ),
          for (final p in e.value) PersonTile(person: p, data: data, onTap: () => context.push('/person/${p.id}')),
        ],
      ],
    );
  }
}

/// Prendas em grupo ainda por comprar, em cartões que deslizam na horizontal.
class _ActiveGroups extends ConsumerWidget {
  const _ActiveGroups();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = (ref.watch(groupsProvider).value ?? const <GiftGroup>[])
        .where((g) => g.purchasedAt == null)
        .toList();
    final parties = (ref.watch(partiesProvider).value ?? const []).where((p) => !p.isPast).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          'Prendas e festas em curso',
          action: parties.isEmpty ? null : 'Festas',
          onAction: () => context.push('/parties'),
        ),
        // Altura pelo conteúdo (texto grande não transborda); os cartões ficam iguais.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          clipBehavior: Clip.none,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final g in groups) ...[_GroupCard(group: g), const SizedBox(width: 12)],
                for (final p in parties) ...[PartyCard(party: p, width: 250), const SizedBox(width: 12)],
                _NewGroupCard(first: groups.isEmpty && parties.isEmpty),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final GiftGroup group;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final paid = g.members.where((m) => g.statusOf(m) != ContributionStatus.pending).length;
    final target = g.targetAmount;
    final progress = target <= 0 ? (g.members.isEmpty ? 0.0 : paid / g.members.length) : g.reportedAmount / target;
    return SizedBox(
      width: 250,
      child: AppCard(
        onTap: () => context.push('/groups/${g.id}'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PARA ${g.celebrantName.toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.eyebrow(context, color: context.palette.accentForeground).copyWith(fontSize: 10),
            ),
            const SizedBox(height: 8),
            Text(g.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTheme.display(context, size: 16)),
            const SizedBox(height: 16),
            const Spacer(),
            SoftProgress(value: progress, semanticsLabel: 'Valor juntado'),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              children: [
                Text(
                  target > 0 ? '${Fmt.money(g.reportedAmount)} de ${Fmt.money(target)}' : 'Valor por definir',
                  style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground),
                ),
                Text(
                  '$paid de ${g.members.length} pagaram',
                  style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewGroupCard extends StatelessWidget {
  const _NewGroupCard({required this.first});

  final bool first;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: first ? 290 : 170,
      child: AppCard(
        color: context.palette.violetSoft,
        raised: false,
        onTap: () => context.push('/groups/new'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(
              icon: LucideIcons.usersRound,
              background: context.colors.secondary.withValues(alpha: 0.18),
              foreground: context.colors.secondary,
            ),
            const SizedBox(height: 16),
            const Spacer(),
            Text(first ? 'Juntem-se para uma prenda' : 'Novo grupo', style: AppTheme.display(context, size: 16)),
            const SizedBox(height: 4),
            Text(
              first ? 'Convida amigos, divide o valor e acompanha quem já pagou.' : 'Divide o valor com amigos',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
            ),
          ],
        ),
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
        onTap: () => single != null ? context.push('/groups/${single.id}') : context.go('/gifts?tab=chats'),
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
