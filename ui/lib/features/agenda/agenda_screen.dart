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

enum _View { week, month, year }

class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  _View _view = _View.week;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Expanded(child: Text('Agenda', style: AppTheme.display(context, size: 30))),
                  IconButton.outlined(
                    tooltip: 'Adicionar',
                    onPressed: () => context.push('/person/new'),
                    icon: const Icon(LucideIcons.plus, size: 20),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_View>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _View.week, label: Text('Semana')),
                    ButtonSegment(value: _View.month, label: Text('Mês')),
                    ButtonSegment(value: _View.year, label: Text('Ano')),
                  ],
                  selected: {_view},
                  onSelectionChanged: (s) => setState(() => _view = s.first),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: DataGate(
                builder: (context, data) => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: switch (_view) {
                    _View.week => _WeekView(key: const ValueKey('w'), data: data),
                    _View.month => _MonthView(key: const ValueKey('m'), data: data),
                    _View.year => _YearView(key: const ValueKey('y'), data: data),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _open(BuildContext context, Person p) => context.push('/person/${p.id}');

class _WeekView extends StatelessWidget {
  const _WeekView({super.key, required this.data});

  final AppData data;

  @override
  Widget build(BuildContext context) {
    final upcoming = data.upcoming;
    const labels = ['Esta semana', 'Próxima semana', 'Daqui a 2 semanas', 'Daqui a 3 semanas'];
    final groups = [
      for (var w = 0; w < labels.length; w++) (labels[w], upcoming.where((p) => p.daysUntil() ~/ 7 == w).toList()),
    ];
    final today = BirthdayUtils.today();

    if (data.people.isEmpty) return const _NoPeople();

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        for (final (i, (label, people)) in groups.indexed) ...[
          SectionTitle(label, padding: const EdgeInsets.fromLTRB(20, 20, 20, 4)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(
              '${Fmt.dayMonth(BirthdayUtils.addDays(today, i * 7))} – ${Fmt.dayMonth(BirthdayUtils.addDays(today, i * 7 + 6))}',
              style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
            ),
          ),
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Sem aniversários.',
                style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground.withValues(alpha: 0.7)),
              ),
            )
          else
            for (final p in people) PersonTile(person: p, data: data, onTap: () => _open(context, p)),
        ],
      ],
    );
  }
}

class _MonthView extends StatefulWidget {
  const _MonthView({super.key, required this.data});

  final AppData data;

  @override
  State<_MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends State<_MonthView> {
  late DateTime _month;
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    final t = BirthdayUtils.today();
    _month = DateTime(t.year, t.month);
  }

  void _shift(int delta) => setState(() {
    _month = DateTime(_month.year, _month.month + delta);
    _selectedDay = null;
  });

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final today = BirthdayUtils.today();
    final byDay = <int, List<Person>>{};
    for (final p in data.people.where((p) => p.month == _month.month)) {
      final d = BirthdayUtils.occurrenceIn(_month.year, p.day, p.month).day;
      byDay.putIfAbsent(d, () => []).add(p);
    }
    final daysInMonth = BirthdayUtils.daysInMonth(_month.month, _month.year);
    final leading = DateTime(_month.year, _month.month).weekday - 1;
    final listDays = (_selectedDay == null ? byDay.keys.toList() : [_selectedDay!])..sort();

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(LucideIcons.chevronLeft)),
              Expanded(
                child: Text(
                  Fmt.monthYear(_month),
                  textAlign: TextAlign.center,
                  style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(onPressed: () => _shift(1), icon: const Icon(LucideIcons.chevronRight)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final d in const ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'])
                      Expanded(
                        child: Center(
                          child: Text(
                            d,
                            style: context.text.labelSmall?.copyWith(
                              color: context.palette.mutedForeground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.9,
                  children: [
                    for (var i = 0; i < leading; i++) const SizedBox.shrink(),
                    for (var day = 1; day <= daysInMonth; day++)
                      _DayCell(
                        day: day,
                        people: byDay[day] ?? const [],
                        data: data,
                        isToday: today == DateTime(_month.year, _month.month, day),
                        selected: _selectedDay == day,
                        onTap: () => setState(() => _selectedDay = _selectedDay == day ? null : day),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedDay == null
                      ? '${byDay.values.fold(0, (a, l) => a + l.length)} aniversários em ${Fmt.monthName(_month.month).toLowerCase()}'
                      : Fmt.weekdayDayMonth(DateTime(_month.year, _month.month, _selectedDay!)),
                  style: context.text.titleSmall,
                ),
              ),
              if (_selectedDay != null)
                TextButton(onPressed: () => setState(() => _selectedDay = null), child: const Text('Ver mês')),
            ],
          ),
        ),
        if (listDays.every((d) => (byDay[d] ?? const []).isEmpty))
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Nenhum aniversário neste ${_selectedDay == null ? 'mês' : 'dia'}.',
              style: TextStyle(color: context.palette.mutedForeground),
            ),
          ),
        for (final d in listDays)
          for (final p in byDay[d] ?? const <Person>[])
            _CompactRow(person: p, data: data, date: DateTime(_month.year, _month.month, d)),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.people,
    required this.data,
    required this.isToday,
    required this.selected,
    required this.onTap,
  });

  final int day;
  final List<Person> people;
  final AppData data;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final has = people.isNotEmpty;
    final Color bg = selected
        ? context.colors.onSurface
        : has
        ? context.palette.accent
        : Colors.transparent;
    final Color fg = selected
        ? context.colors.surface
        : has
        ? context.palette.accentForeground
        : context.colors.onSurface;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isToday && !selected ? BorderSide(color: context.colors.primary, width: 1.5) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: has ? onTap : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: context.text.bodyMedium?.copyWith(
                  color: fg,
                  fontWeight: has || isToday ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final p in people.take(3))
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: selected ? context.colors.surface : personColor(p, data),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({required this.person, required this.data, required this.date});

  final Person person;
  final AppData data;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final age = person.year == null ? null : date.year - person.year!;
    final days = person.daysUntil();
    return InkWell(
      onTap: () => _open(context, person),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            DateTile(date: date, highlight: days == 0),
            const SizedBox(width: 14),
            PersonAvatar(person: person, color: personColor(person, data), size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(person.name, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    [Fmt.weekday(date), if (age != null && age > 0) 'faz $age'].join(' · '),
                    style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YearView extends StatelessWidget {
  const _YearView({super.key, required this.data});

  final AppData data;

  @override
  Widget build(BuildContext context) {
    if (data.people.isEmpty) return const _NoPeople();
    final today = BirthdayUtils.today();
    final months = [for (var i = 0; i < 12; i++) DateTime(today.year, today.month + i)];

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        for (final m in months)
          Builder(
            builder: (context) {
              final people = data.people.where((p) => p.month == m.month).toList()
                ..sort((a, b) => a.day.compareTo(b.day));
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: Row(
                          children: [
                            Text(Fmt.monthName(m.month), style: AppTheme.display(context, size: 20)),
                            const SizedBox(width: 8),
                            Text('${m.year}', style: TextStyle(color: context.palette.mutedForeground)),
                            const Spacer(),
                            Pill(
                              label: people.isEmpty ? '—' : '${people.length}',
                              background: people.isEmpty ? null : context.palette.accent,
                              foreground: people.isEmpty ? null : context.palette.accentForeground,
                            ),
                          ],
                        ),
                      ),
                      if (people.isNotEmpty) const Divider(),
                      for (final p in people)
                        _CompactRow(person: p, data: data, date: BirthdayUtils.occurrenceIn(m.year, p.day, p.month)),
                      if (people.isNotEmpty) const SizedBox(height: 6),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _NoPeople extends StatelessWidget {
  const _NoPeople();

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: EmptyState(
        icon: LucideIcons.calendarHeart,
        title: 'A agenda está vazia',
        message: 'Quando adicionares aniversários, vais vê-los aqui organizados por semana, mês e ano.',
        action: FilledButton(
          onPressed: () => context.push('/person/new'),
          style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
          child: const Text('Adicionar aniversário'),
        ),
      ),
    ),
  );
}
