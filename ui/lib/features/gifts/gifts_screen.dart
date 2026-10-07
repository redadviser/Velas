import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/data_gate.dart';
import '../../data/models/models.dart';
import '../../core/providers.dart';
import '../../data/models/group_models.dart';
import '../groups/group_widgets.dart';
import 'gift_widgets.dart';

class GiftsScreen extends ConsumerStatefulWidget {
  const GiftsScreen({super.key});

  @override
  ConsumerState<GiftsScreen> createState() => _GiftsScreenState();
}

class _GiftsScreenState extends ConsumerState<GiftsScreen> {
  bool _showPurchased = false;
  bool _groupsTab = false;
  String? _tabParam;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Permite abrir diretamente a aba de grupos: /gifts?tab=groups
    final tab = GoRouterState.of(context).uri.queryParameters['tab'];
    if (tab != _tabParam) {
      _tabParam = tab;
      if (tab != null) _groupsTab = tab == 'groups';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final toPay = (ref.watch(groupsProvider).value ?? const <GiftGroup>[]).where((g) {
      final me = g.memberFor(user?.id);
      return g.purchasedAt == null && me != null && g.statusOf(me) == ContributionStatus.pending;
    }).length;

    final header = [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Text('Presentes', style: AppTheme.display(context, size: 30)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            _Tab(label: 'Ideias', selected: !_groupsTab, onTap: () => setState(() => _groupsTab = false)),
            const SizedBox(width: 20),
            _Tab(label: 'Em grupo', badge: toPay, selected: _groupsTab, onTap: () => setState(() => _groupsTab = true)),
          ],
        ),
      ),
      const Divider(height: 1),
    ];

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-gifts',
        onPressed: () => _groupsTab ? context.push('/groups/new') : pickPersonThenAddGift(context, ref),
        icon: const Icon(LucideIcons.plus, size: 20),
        label: Text(_groupsTab ? 'Novo grupo' : 'Nova ideia'),
      ),
      body: SafeArea(
        bottom: false,
        child: _groupsTab
            ? RefreshIndicator(
                onRefresh: () => ref.read(groupsProvider.notifier).refresh(),
                child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [...header, const GroupsList()]),
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
                                label: 'Por comprar',
                                value: '${pending.length}',
                                sub: toSpend > 0 ? '≈ ${Fmt.money(toSpend)}' : null,
                              ),
                              Container(width: 1, height: 44, color: context.palette.border),
                              _Summary(
                                label: 'Comprados',
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
                          segments: const [
                            ButtonSegment(value: false, label: Text('Por comprar')),
                            ButtonSegment(value: true, label: Text('Comprados')),
                          ],
                          selected: {_showPurchased},
                          onSelectionChanged: (s) => setState(() => _showPurchased = s.first),
                        ),
                      ),
                      if (groups.isEmpty)
                        EmptyState(
                          icon: LucideIcons.gift,
                          title: _showPurchased ? 'Nada comprado ainda' : 'Sem ideias pendentes',
                          message: _showPurchased
                              ? 'Quando marcares um presente como comprado, aparece aqui.'
                              : 'Guarda ideias de presentes ao longo do ano e chega ao dia sem stress.',
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? context.colors.primary : Colors.transparent, width: 2.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.text.titleSmall?.copyWith(
                fontSize: 15,
                color: selected ? context.colors.onSurface : context.palette.mutedForeground,
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
                                : 'Orçamento ${Fmt.money(person.giftBudget!)} · gasto ${Fmt.money(allGifts.where((g) => g.purchased).fold<double>(0, (a, g) => a + (g.price ?? 0)))}',
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
