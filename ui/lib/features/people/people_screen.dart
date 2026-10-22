import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/text.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/data_gate.dart';
import '../../data/models/models.dart';
import 'birthday_request.dart';

enum _Sort { upcoming, name }

class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _category; // null = todas
  _Sort _sort = _Sort.upcoming;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Person> _filter(AppData data) {
    final q = foldText(_query.trim());
    final list =
        (_sort == _Sort.upcoming
                ? data.upcoming
                : ([...data.people]..sort((a, b) => foldText(a.name).compareTo(foldText(b.name)))))
            .where((p) => _category == null || p.categoryId == _category)
            .where((p) => q.isEmpty || foldText('${p.name} ${p.relation} ${p.notes}').contains(q))
            .toList();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-people',
        onPressed: () => context.push('/person/new'),
        icon: const Icon(LucideIcons.userPlus, size: 20),
        label: const Text('Adicionar'),
      ),
      body: SafeArea(
        bottom: false,
        child: DataGate(
          builder: (context, data) {
            final people = _filter(data);
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                    child: Row(
                      children: [
                        Expanded(child: Text('Pessoas', style: AppTheme.display(context, size: 30))),
                        // O link de pedido está no ecrã dos contactos.
                        IconButton(
                          tooltip: 'Importar do calendário',
                          icon: const Icon(LucideIcons.calendarDays, size: 20),
                          onPressed: () => context.push('/people/import?from=calendar'),
                        ),
                        IconButton(
                          tooltip: 'Adicionar dos contactos',
                          icon: const Icon(LucideIcons.contactRound, size: 20),
                          onPressed: () => context.push('/people/import'),
                        ),
                        PopupMenuButton<_Sort>(
                          tooltip: 'Ordenar',
                          icon: const Icon(LucideIcons.arrowUpDown, size: 20),
                          initialValue: _sort,
                          onSelected: (s) => setState(() => _sort = s),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: _Sort.upcoming, child: Text('Próximo aniversário')),
                            PopupMenuItem(value: _Sort.name, child: Text('Nome (A–Z)')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Pesquisar por nome, relação ou nota',
                        prefixIcon: const Icon(LucideIcons.search, size: 18),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(LucideIcons.x, size: 18),
                                onPressed: () => setState(() {
                                  _search.clear();
                                  _query = '';
                                }),
                              ),
                      ),
                    ),
                  ),
                ),
                // Datas deixadas pelo link à espera de confirmação.
                if ((ref.watch(birthdayRequestProvider).value?.pending ?? 0) > 0)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: _PendingBanner(count: ref.watch(birthdayRequestProvider).value!.pending),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 56,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                      children: [
                        _FilterChip(
                          label: 'Todos · ${data.people.length}',
                          selected: _category == null,
                          onTap: () => setState(() => _category = null),
                        ),
                        for (final c in data.categories)
                          _FilterChip(
                            label: c.name,
                            dot: swatch(c.color),
                            selected: _category == c.id,
                            onTap: () => setState(() => _category = _category == c.id ? null : c.id),
                          ),
                      ],
                    ),
                  ),
                ),
                if (data.people.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: LucideIcons.usersRound,
                      title: 'Ainda não há ninguém',
                      message: 'Adiciona familiares, amigos e colegas para nunca falhares um aniversário.',
                      action: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton.icon(
                            onPressed: () => context.push('/people/import'),
                            icon: const Icon(LucideIcons.contactRound, size: 18),
                            label: const Text('Adicionar dos contactos'),
                            style: FilledButton.styleFrom(minimumSize: const Size(240, 52)),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => context.push('/people/import?from=calendar'),
                            icon: const Icon(LucideIcons.calendarDays, size: 18),
                            label: const Text('Importar do calendário'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(240, 48)),
                          ),
                          const SizedBox(height: 4),
                          TextButton.icon(
                            onPressed: () => context.push('/person/new'),
                            icon: const Icon(LucideIcons.userPlus, size: 18),
                            label: const Text('Adicionar pessoa'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (people.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: LucideIcons.searchX,
                      title: 'Sem resultados',
                      message: 'Não encontrámos ninguém com esses critérios.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 100),
                    sliver: SliverList.builder(
                      itemCount: people.length,
                      itemBuilder: (context, i) => PersonTile(
                        person: people[i],
                        data: data,
                        showDate: _sort == _Sort.upcoming,
                        onTap: () => context.push('/person/${people[i].id}'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.dot});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? context.colors.onSurface : context.palette.card,
        shape: StadiumBorder(side: BorderSide(color: selected ? Colors.transparent : context.palette.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dot != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: context.text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? context.colors.surface : context.colors.onSurface,
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

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final fg = context.palette.accentForeground;
    return AppCard(
      color: context.palette.accent,
      onTap: () => context.push('/people/requests'),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Icon(LucideIcons.inbox, size: 20, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              count == 1 ? '1 aniversário à espera de confirmação' : '$count aniversários à espera de confirmação',
              style: context.text.titleSmall?.copyWith(color: fg),
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: fg),
        ],
      ),
    );
  }
}
