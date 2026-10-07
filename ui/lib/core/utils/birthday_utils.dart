import 'package:intl/intl.dart';

/// Cálculos de datas de aniversário. Todas as funções trabalham ao nível do
/// dia (sem horas) para que "hoje" e "amanhã" sejam sempre coerentes.
class BirthdayUtils {
  const BirthdayUtils._();

  static DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Soma dias de calendário. Ao contrário de `add(Duration(days: n))`, não
  /// é afetado pela mudança de hora (ex.: 25 de outubro em Portugal).
  static DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

  static bool isLeapYear(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

  /// Data do aniversário num determinado ano. Quem nasceu a 29 de fevereiro
  /// celebra a 28 nos anos não bissextos.
  static DateTime occurrenceIn(int year, int day, int month) {
    if (month == 2 && day == 29 && !isLeapYear(year)) return DateTime(year, 2, 28);
    return DateTime(year, month, day);
  }

  static DateTime nextOccurrence(int day, int month, {DateTime? from}) {
    final base = from == null ? today() : DateTime(from.year, from.month, from.day);
    final thisYear = occurrenceIn(base.year, day, month);
    return thisYear.isBefore(base) ? occurrenceIn(base.year + 1, day, month) : thisYear;
  }

  static int daysUntil(int day, int month, {DateTime? from}) {
    final base = from == null ? today() : DateTime(from.year, from.month, from.day);
    // Usa UTC para não ser afetado pela mudança de hora.
    final a = DateTime.utc(base.year, base.month, base.day);
    final n = nextOccurrence(day, month, from: base);
    return DateTime.utc(n.year, n.month, n.day).difference(a).inDays;
  }

  /// Idade que a pessoa vai fazer no próximo aniversário (ou hoje).
  static int? turningAge(int day, int month, int? year) {
    if (year == null) return null;
    return nextOccurrence(day, month).year - year;
  }

  static int? currentAge(int day, int month, int? year) {
    if (year == null) return null;
    final t = today();
    final hadBirthday = !occurrenceIn(t.year, day, month).isAfter(t);
    return t.year - year - (hadBirthday ? 0 : 1);
  }

  static int daysInMonth(int month, [int? year]) {
    if (month == 2) return (year == null || isLeapYear(year)) ? 29 : 28;
    return const [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
  }
}

/// Formatação de datas em português de Portugal.
class Fmt {
  const Fmt._();

  static const _locale = 'pt_PT';

  static String dayMonth(DateTime d) => DateFormat("d 'de' MMMM", _locale).format(d);
  static String fullDate(DateTime d) => DateFormat("d 'de' MMMM 'de' y", _locale).format(d);
  static String weekdayDayMonth(DateTime d) => _cap(DateFormat("EEEE, d 'de' MMMM", _locale).format(d));
  static String weekday(DateTime d) => _cap(DateFormat('EEEE', _locale).format(d));
  static String weekdayShort(DateTime d) => _cap(DateFormat('EEE', _locale).format(d).replaceAll('.', ''));
  static String monthName(int month) => _cap(DateFormat('MMMM', _locale).format(DateTime(2000, month)));
  static String monthShort(int month) =>
      DateFormat('MMM', _locale).format(DateTime(2000, month)).replaceAll('.', '').toUpperCase();
  static String monthYear(DateTime d) => _cap(DateFormat("MMMM 'de' y", _locale).format(d));

  static String birthDate(int day, int month, int? year) =>
      year == null ? dayMonth(DateTime(2000, month, day)) : fullDate(DateTime(year, month, day));

  static String money(num v) =>
      NumberFormat.currency(locale: _locale, symbol: '€', decimalDigits: v % 1 == 0 ? 0 : 2).format(v);

  static String relativeDays(int days) => switch (days) {
    0 => 'Hoje',
    1 => 'Amanhã',
    < 7 => 'Daqui a $days dias',
    < 14 => 'Daqui a 1 semana',
    < 31 => 'Daqui a ${days ~/ 7} semanas',
    _ => 'Daqui a $days dias',
  };

  static String shortRelative(int days) => switch (days) {
    0 => 'Hoje',
    1 => 'Amanhã',
    _ => '$days dias',
  };

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
