import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';

typedef BirthDate = ({int day, int month, int? year});

/// Seletor em rodas (dia / mês / ano). O ano é opcional porque muitas vezes
/// sabemos o dia de anos de alguém mas não a idade.
Future<BirthDate?> showBirthdayPicker(BuildContext context, {BirthDate? initial}) {
  return showModalBottomSheet<BirthDate>(
    context: context,
    builder: (_) => _BirthdayPicker(initial: initial ?? (day: 1, month: 1, year: null)),
  );
}

class _BirthdayPicker extends StatefulWidget {
  const _BirthdayPicker({required this.initial});

  final BirthDate initial;

  @override
  State<_BirthdayPicker> createState() => _BirthdayPickerState();
}

class _BirthdayPickerState extends State<_BirthdayPicker> {
  late int _day = widget.initial.day;
  late int _month = widget.initial.month;
  late int? _year = widget.initial.year;

  final int _thisYear = DateTime.now().year;
  late final List<int?> _years = [null, for (var y = _thisYear; y >= 1900; y--) y];

  late final _dayCtrl = FixedExtentScrollController(initialItem: _day - 1);
  late final _monthCtrl = FixedExtentScrollController(initialItem: _month - 1);
  late final _yearCtrl = FixedExtentScrollController(initialItem: _years.indexOf(_year));

  @override
  void dispose() {
    _dayCtrl.dispose();
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  int get _maxDay => BirthdayUtils.daysInMonth(_month, _year);

  void _clampDay() {
    if (_day > _maxDay) {
      _day = _maxDay;
      _dayCtrl.animateToItem(_day - 1, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  bool get _isFuture => _year != null && DateTime(_year!, _month, _day).isAfter(BirthdayUtils.today());

  @override
  Widget build(BuildContext context) {
    final style = context.text.titleMedium!;
    Widget wheel({
      required FixedExtentScrollController controller,
      required int count,
      required String Function(int) label,
      required ValueChanged<int> onChanged,
      int flex = 1,
      bool Function(int)? disabled,
    }) => Expanded(
      flex: flex,
      child: CupertinoPicker(
        scrollController: controller,
        itemExtent: 42,
        selectionOverlay: const SizedBox.shrink(),
        onSelectedItemChanged: onChanged,
        children: [
          for (var i = 0; i < count; i++)
            Center(
              child: Text(
                label(i),
                style: style.copyWith(
                  color: disabled?.call(i) == true ? context.palette.mutedForeground.withValues(alpha: 0.4) : null,
                ),
              ),
            ),
        ],
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Data de aniversário', style: AppTheme.display(context, size: 22)),
            const SizedBox(height: 4),
            Text(
              _year == null ? Fmt.dayMonth(DateTime(2000, _month, _day)) : Fmt.fullDate(DateTime(_year!, _month, _day)),
              style: TextStyle(color: context.palette.mutedForeground),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 210,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 42,
                    decoration: BoxDecoration(color: context.palette.muted, borderRadius: BorderRadius.circular(12)),
                  ),
                  Row(
                    children: [
                      wheel(
                        controller: _dayCtrl,
                        count: 31,
                        label: (i) => '${i + 1}',
                        disabled: (i) => i + 1 > _maxDay,
                        onChanged: (i) => setState(() {
                          _day = i + 1;
                          _clampDay();
                        }),
                      ),
                      wheel(
                        controller: _monthCtrl,
                        count: 12,
                        flex: 2,
                        label: (i) => Fmt.monthName(i + 1),
                        onChanged: (i) => setState(() {
                          _month = i + 1;
                          _clampDay();
                        }),
                      ),
                      wheel(
                        controller: _yearCtrl,
                        count: _years.length,
                        flex: 2,
                        label: (i) => _years[i]?.toString() ?? 'Sem ano',
                        onChanged: (i) => setState(() {
                          _year = _years[i];
                          _clampDay();
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isFuture
                  ? 'A data não pode estar no futuro.'
                  : 'Não sabes o ano? Escolhe "Sem ano" — só não mostramos a idade.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(
                color: _isFuture ? context.colors.error : context.palette.mutedForeground,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isFuture ? null : () => Navigator.pop(context, (day: _day, month: _month, year: _year)),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }
}
