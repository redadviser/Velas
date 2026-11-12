import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/data_gate.dart';
import '../../data/models/models.dart';
import '../../core/providers.dart';
import '../chat/conversations_list.dart';
import 'gift_widgets.dart';
import '../../core/constants.dart';
import '../../core/i18n/translations.dart';

class GiftsScreen extends ConsumerStatefulWidget {
  const GiftsScreen({super.key});

  @override
  ConsumerState<GiftsScreen> createState() => _GiftsScreenState();
}

enum _View { ongoing, done, ideas }

class _GiftsScreenState extends ConsumerState<GiftsScreen> {
  bool _showPurchased = false;
  var _view = _View.ongoing;
  String? _tabParam;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Permite abrir diretamente um separador: /gifts?tab=chats (ou groups), ?tab=done ou ?tab=ideas
    final tab = GoRouterState.of(context).uri.queryParameters['tab'];
    if (tab != _tabParam) {
      _tabParam = tab;
      if (tab != null) {
        _view = switch (tab) {
          'ideas' => _View.ideas,
          'done' => _View.done,
          _ => _View.ongoing,
        };
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final badge = ref.watch(conversationsBadgeProvider);
    final requests = ref.watch(incomingFriendRequestsProvider);
    final chat = ref.watch(chatRepositoryProvider) != null;
    final plans = _view != _View.ideas;

    final header = [
      Padding(
        padding: EdgeInsets.fromLTRB(20, 16, chat ? 8 : 20, 12),
        child: Row(
          children: [
            Expanded(child: Text(context.tr('Prendas'), style: AppTheme.display(context, size: 30))),
            if (chat)
              IconButton(
                tooltip: context.tr(Keys.chatFriendsTooltip),
                onPressed: () => context.push('/friends'),
                icon: Badge(
                  isLabelVisible: requests > 0,
                  label: Text('$requests'),
                  child: const Icon(LucideIcons.usersRound, size: 22),
                ),
              ),
            // Definições gerais das conversas (privacidade e notificações).
            if (chat)
              IconButton(
                tooltip: context.tr(Keys.chatInfoAllSettings),
                onPressed: () => context.push('/chat-settings'),
                icon: const Icon(LucideIcons.settings, size: 22),
              ),
          ],
        ),
      ),
      const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 14), child: _StatsBanner()),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Row(
          spacing: 8,
          children: [
            for (final (v, label) in [
              (_View.ongoing, context.tr('Em curso')),
              (_View.done, context.tr('Concluídos')),
              (_View.ideas, context.tr('Ideias guardadas')),
            ])
              _Tab(
                label: label,
                badge: v == _View.ongoing ? badge : 0,
                selected: _view == v,
                onTap: () => setState(() => _view = v),
              ),
          ],
        ),
      ),
    ];

    return Scaffold(
      // Prendas em grupo e festas criam-se no "+" do meio.
      floatingActionButton: plans
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab-gifts',
              onPressed: () => pickPersonThenAddGift(context, ref),
              icon: const Icon(LucideIcons.plus, size: 20),
              label: Text(context.tr('Nova ideia')),
            ),
      body: SafeArea(
        bottom: false,
        child: plans
            ? RefreshIndicator(
                onRefresh: () async {
                  await Future.wait([
                    ref.read(groupsProvider.notifier).refresh(),
                    if (ref.read(partyRepositoryProvider) != null) ref.read(partiesProvider.notifier).refresh(),
                    if (chat) ref.read(conversationsProvider.notifier).refresh(),
                    if (chat) ref.read(friendsProvider.notifier).refresh(),
                  ]);
                },
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 100),
                  children: [
                    ...header,
                    PlansList(done: _view == _View.done),
                  ],
                ),
              )
            : DataGate(
                builder: (context, data) {
                  final pending = data.gifts.where((g) => !g.purchased).toList();
                  final purchased = data.gifts.where((g) => g.purchased).toList();
                  final spent = purchased.fold<double>(0, (a, g) => a + (g.price ?? 0));
                  final toSpend = pending.fold<double>(0, (a, g) => a + (g.price ?? 0));
                  final visible = _showPurchased ? purchased : pending;

                  // Agrupa por pessoa, pela ordem do próximo aniversário.
                  final groups = [
                    for (final p in data.upcoming)
                      if (visible.any((g) => g.personId == p.id))
                        (p, visible.where((g) => g.personId == p.id).toList()),
                  ];

                  return ListView(
                    padding: const EdgeInsets.only(bottom: 100),
                    children: [
                      ...header,
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: AppCard(
                          child: Row(
                            children: [
                              _Summary(
                                label: context.tr('Por comprar'),
                                value: '${pending.length}',
                                sub: toSpend > 0 ? '≈ ${Fmt.money(toSpend)}' : null,
                              ),
                              Container(width: 1, height: 44, color: context.palette.border),
                              _Summary(
                                label: context.tr('Comprados'),
                                value: '${purchased.length}',
                                sub: spent > 0 ? Fmt.money(spent) : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(value: false, label: Text(context.tr('Por comprar'))),
                            ButtonSegment(value: true, label: Text(context.tr('Comprados'))),
                          ],
                          selected: {_showPurchased},
                          onSelectionChanged: (s) => setState(() => _showPurchased = s.first),
                        ),
                      ),
                      if (groups.isEmpty)
                        EmptyState(
                          icon: LucideIcons.gift,
                          title: _showPurchased
                              ? context.tr('Nada comprado ainda')
                              : context.tr('Sem ideias pendentes'),
                          message: _showPurchased
                              ? context.tr('Quando marcares um presente como comprado, aparece aqui.')
                              : context.tr('Guarda ideias de presentes ao longo do ano e chega ao dia sem stress.'),
                        )
                      else
                        for (final (person, gifts) in groups) _PersonGroup(person: person, gifts: gifts, data: data),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, required this.onTap, this.badge = 0});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    // Pílula como os filtros do resto da app: escolhida = tinta cheia.
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? context.colors.onSurface : context.palette.card,
        shape: StadiumBorder(side: BorderSide(color: selected ? Colors.transparent : context.palette.border)),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: context.text.titleSmall?.copyWith(
                    fontSize: 14,
                    color: selected ? context.colors.surface : context.palette.mutedForeground,
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: context.colors.primary, borderRadius: BorderRadius.circular(99)),
                    child: Text(
                      '$badge',
                      style: TextStyle(color: context.colors.onPrimary, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.label, required this.value, this.sub});

  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(value, style: AppTheme.display(context, size: 26)),
        Text(label, style: context.text.labelMedium?.copyWith(color: context.palette.mutedForeground)),
        if (sub != null) Text(sub!, style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground)),
      ],
    ),
  );
}

class _PersonGroup extends ConsumerWidget {
  const _PersonGroup({required this.person, required this.gifts, required this.data});

  final Person person;
  final List<GiftIdea> gifts;
  final AppData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allGifts = data.giftsFor(person.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => context.push('/person/${person.id}'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Row(
                  children: [
                    PersonAvatar(person: person, color: personColor(person, data), size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(person.name, style: context.text.titleSmall),
                          Text(
                            person.giftBudget == null
                                ? Fmt.dayMonth(person.nextBirthday())
                                : context.tr('Orçamento {budget} · gasto {spent}', {
                                    'budget': Fmt.money(person.giftBudget!),
                                    'spent': Fmt.money(
                                      allGifts.where((g) => g.purchased).fold<double>(0, (a, g) => a + (g.price ?? 0)),
                                    ),
                                  }),
                            style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                          ),
                        ],
                      ),
                    ),
                    DaysPill(days: person.daysUntil()),
                  ],
                ),
              ),
            ),
            const Divider(),
            for (final g in gifts) GiftRow(gift: g, padding: const EdgeInsets.only(left: 4, right: 8)),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

/// Resumo das prendas em grupo em curso, em violeta.
class _StatsBanner extends ConsumerWidget {
  const _StatsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = (ref.watch(groupsProvider).value ?? const []).where((g) => g.purchasedAt == null).toList();
    final parties = (ref.watch(partiesProvider).value ?? const []).where((p) => !p.isPast).length;
    final active = groups.length + parties;
    final collected = groups.fold<double>(0, (a, g) => a + g.confirmedAmount);

    Widget stat(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: AppTheme.display(context, size: 24, color: context.colors.secondary),
            ),
          ),
          Text(label, style: context.text.labelSmall?.copyWith(color: context.colors.onSurface)),
        ],
      ),
    );
    Widget divider() => Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: context.palette.border,
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(21), color: context.palette.violetSoft),
      child: Row(
        children: [
          stat('$active', active == 1 ? context.tr('grupo ativo') : context.tr('grupos ativos')),
          divider(),
          stat(Fmt.money(collected), context.tr('reunidos')),
        ],
      ),
    );
  }
}
