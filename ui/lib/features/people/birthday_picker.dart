import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';

typedef BirthDate = ({int day, int month, int? year});

/// Seletor de data em calendário. Numa data nova o caminho é ano → mês → dia
/// (três toques); ao editar abre logo no mês da data. O ano é opcional porque
/// muitas vezes sabemos o dia de anos de alguém mas não a idade.
Future<BirthDate?> showBirthdayPicker(BuildContext context, {BirthDate? initial}) {
  return showModalBottomSheet<BirthDate>(
    context: context,
    // A altura vem do conteúdo (por omissão o modal fica limitado a 9/16 do ecrã).
    isScrollControlled: true,
    builder: (_) => _BirthdayPicker(initial: initial),
  );
}

enum _View { days, months, years }

const _minYear = 1900;
const _cellHeight = 44.0;
const _weekdayRow = 28.0;

/// Altura fixa para o modal não saltar ao mudar de vista (6 semanas no máximo).
const _bodyHeight = _cellHeight * 6 + _weekdayRow;

const _weekdays = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];

class _BirthdayPicker extends StatefulWidget {
  const _BirthdayPicker({required this.initial});

  final BirthDate? initial;

  @override
  State<_BirthdayPicker> createState() => _BirthdayPickerState();
}

class _BirthdayPickerState extends State<_BirthdayPicker> {
  final _today = BirthdayUtils.today();

  late int? _day = widget.initial?.day;
  late int _month = widget.initial?.month ?? _today.month;
  late int? _year = widget.initial?.year;

  /// Numa data nova "Sem ano" só fica marcado depois de escolhido.
  late bool _yearPicked = widget.initial != null;
  late _View _view = widget.initial == null ? _View.years : _View.days;

  int get _maxDay => BirthdayUtils.daysInMonth(_month, _year);

  bool _isFutureMonth(int month, int? year) =>
      year != null && DateTime(year, month).isAfter(DateTime(_today.year, _today.month));

  bool _isFutureDay(int day) => _year != null && DateTime(_year!, _month, day).isAfter(_today);

  bool get _isFuture => _day != null && _isFutureDay(_day!);

  void _clampDay() {
    if (_day != null && _day! > _maxDay) _day = _maxDay;
  }

  /// Mês anterior/seguinte, ou null se sair do intervalo permitido.
  ({int month, int? year})? _shifted(int delta) {
    var m = _month + delta;
    var y = _year;
    if (m < 1) {
      m = 12;
      if (y != null) y--;
    } else if (m > 12) {
      m = 1;
      if (y != null) y++;
    }
    if (y != null && (y < _minYear || _isFutureMonth(m, y))) return null;
    return (month: m, year: y);
  }

  void _shift(int delta) {
    final s = _shifted(delta);
    if (s == null) return;
    setState(() {
      _month = s.month;
      _year = s.year;
      _clampDay();
    });
  }

  void _pickYear(int? year) => setState(() {
    _year = year;
    _yearPicked = true;
    if (_isFutureMonth(_month, year)) _month = _today.month;
    _clampDay();
    // Sem dia escolhido segue para o mês; ao corrigir só o ano volta ao calendário.
    _view = _day == null ? _View.months : _View.days;
  });

  void _pickMonth(int month) => setState(() {
    _month = month;
    _clampDay();
    _view = _View.days;
  });

  void _toggle(_View v) => setState(() => _view = _view == v ? _View.days : v);

  String get _summary {
    if (_day == null) {
      return switch (_view) {
        _View.years => 'Escolhe o ano',
        _View.months => 'Escolhe o mês',
        _View.days => 'Escolhe o dia',
      };
    }
    return Fmt.birthDate(_day!, _month, _year);
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.mutedForeground;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Data de aniversário', style: AppTheme.display(context, size: 22)),
            const SizedBox(height: 4),
            Text(_summary, style: TextStyle(color: muted)),
            const SizedBox(height: 12),
            _header(context),
            const SizedBox(height: 8),
            SizedBox(
              height: _bodyHeight,
              child: switch (_view) {
                _View.days => _daysGrid(context),
                _View.months => _monthsGrid(),
                _View.years => _YearGrid(
                  years: [for (var y = _today.year; y >= _minYear; y--) y],
                  selected: _year,
                  noYearSelected: _yearPicked && _year == null,
                  onPick: _pickYear,
                ),
              },
            ),
            const SizedBox(height: 8),
            Text(
              _isFuture
                  ? 'A data não pode estar no futuro.'
                  : _year == null && _yearPicked
                  ? 'Sem ano — só não mostramos a idade.'
                  : 'Não sabes o ano? Toca no ano e escolhe "Sem ano".',
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(color: _isFuture ? context.colors.error : muted),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _day == null || _isFuture
                  ? null
                  : () => Navigator.pop(context, (day: _day!, month: _month, year: _year)),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final arrows = _view == _View.days;
    Widget arrow(int delta, IconData icon, String tooltip) => Visibility(
      visible: arrows,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: IconButton(
        tooltip: tooltip,
        onPressed: _shifted(delta) == null ? null : () => _shift(delta),
        icon: Icon(icon),
      ),
    );

    return Row(
      children: [
        arrow(-1, Icons.chevron_left, 'Mês anterior'),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              _HeaderChip(
                label: Fmt.monthName(_month),
                open: _view == _View.months,
                onTap: () => _toggle(_View.months),
              ),
              _HeaderChip(
                label: _year?.toString() ?? (_yearPicked ? 'Sem ano' : 'Ano'),
                open: _view == _View.years,
                onTap: () => _toggle(_View.years),
              ),
            ],
          ),
        ),
        arrow(1, Icons.chevron_right, 'Mês seguinte'),
      ],
    );
  }

  Widget _daysGrid(BuildContext context) {
    // Sem ano o dia da semana não existe, por isso a grelha começa sempre no 1.
    final lead = _year == null ? 0 : DateTime(_year!, _month).weekday - 1;
    final cells = <int?>[for (var i = 0; i < lead; i++) null, for (var d = 1; d <= _maxDay; d++) d];
    final isCurrentMonth = _year == _today.year && _month == _today.month;

    return Column(
      children: [
        SizedBox(
          height: _weekdayRow,
          child: _year == null
              ? null
              : Row(
                  children: [
                    for (final w in _weekdays)
                      Expanded(
                        child: Center(
                          child: Text(
                            w,
                            style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        for (var r = 0; r * 7 < cells.length; r++)
          SizedBox(
            height: _cellHeight,
            child: Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: switch (r * 7 + c < cells.length ? cells[r * 7 + c] : null) {
                      null => const SizedBox.shrink(),
                      final d => _Cell(
                        label: '$d',
                        selected: d == _day,
                        enabled: !_isFutureDay(d),
                        outlined: isCurrentMonth && d == _today.day,
                        onTap: () => setState(() => _day = d),
                      ),
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _monthsGrid() {
    return Column(
      children: [
        for (var r = 0; r < 4; r++)
          Expanded(
            child: Row(
              children: [
                for (var c = 1; c <= 3; c++)
                  Expanded(
                    child: _Cell(
                      label: Fmt.monthName(r * 3 + c),
                      selected: r * 3 + c == _month,
                      enabled: !_isFutureMonth(r * 3 + c, _year),
                      onTap: () => _pickMonth(r * 3 + c),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Grelha de anos (mais recentes primeiro) com "Sem ano" à cabeça. Abre já
/// posicionada no ano escolhido.
class _YearGrid extends StatefulWidget {
  const _YearGrid({required this.years, required this.selected, required this.noYearSelected, required this.onPick});

  final List<int> years;
  final int? selected;
  final bool noYearSelected;
  final ValueChanged<int?> onPick;

  @override
  State<_YearGrid> createState() => _YearGridState();
}

class _YearGridState extends State<_YearGrid> {
  static const _columns = 4;

  late final _scroll = ScrollController(initialScrollOffset: _initialOffset());

  double _initialOffset() {
    final s = widget.selected;
    if (s == null) return 0;
    final index = widget.years.indexOf(s) + 1; // +1 por causa do "Sem ano".
    final row = index ~/ _columns;
    return (row * _cellHeight - (_bodyHeight - _cellHeight) / 2).clamp(0, double.infinity);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = <int?>[null, ...widget.years];
    return GridView.builder(
      controller: _scroll,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        mainAxisExtent: _cellHeight,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final y = items[i];
        return _Cell(
          label: y?.toString() ?? 'Sem ano',
          selected: y == null ? widget.noYearSelected : y == widget.selected,
          onTap: () => widget.onPick(y),
        );
      },
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.label, required this.open, required this.onTap});

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      iconAlignment: IconAlignment.end,
      icon: Icon(open ? Icons.expand_less : Icons.expand_more, size: 20),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: context.colors.onSurface,
        backgroundColor: open ? context.palette.muted : null,
        textStyle: context.text.titleMedium,
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
    this.outlined = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool enabled;

  /// Marca o dia de hoje.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shape = StadiumBorder(
      side: outlined && !selected ? BorderSide(color: colors.primary) : BorderSide.none,
    );
    final color = selected
        ? colors.onPrimary
        : enabled
        ? colors.onSurface
        : context.palette.mutedForeground.withValues(alpha: 0.4);

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: selected ? colors.primary : Colors.transparent,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: enabled ? onTap : null,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: context.text.bodyLarge?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
