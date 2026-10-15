import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../core/i18n/translations.dart';
import '../../core/utils/birthday_utils.dart';
import '../../data/models/chat_models.dart';

/// Datas, horas e frases das conversas na língua escolhida.
abstract final class ChatFormat {
  static Translations get _t => Translations.current;
  static String get _locale => _t.dateLocale;

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static int _daysAgo(DateTime d) => BirthdayUtils.today().difference(DateTime(d.year, d.month, d.day)).inDays;

  /// "14:05".
  static String time(DateTime d) => _t.time(d);

  /// Na lista de conversas: hoje "14:05", ontem "Ontem", esta semana "Ter", antes a data curta.
  static String listTime(DateTime d) {
    final days = _daysAgo(d);
    if (days <= 0) return time(d);
    if (days == 1) return _t.get(Keys.commonYesterday);
    if (days < 7) return _cap(DateFormat.E(_locale).format(d).replaceAll('.', ''));
    return DateFormat.yMd(_locale).format(d);
  }

  /// Separador de dias dentro da conversa.
  static String day(DateTime d) {
    final days = _daysAgo(d);
    if (days <= 0) return _t.get(Keys.commonToday);
    if (days == 1) return _t.get(Keys.commonYesterday);
    if (days < 7) return _cap(DateFormat.EEEE(_locale).format(d));
    return _cap(
      d.year == DateTime.now().year
          ? DateFormat.MMMMEEEEd(_locale).format(d)
          : DateFormat.yMMMMEEEEd(_locale).format(d),
    );
  }

  /// Quando alguém viu: "14:05", "Ontem, 14:05" ou "12/03/2025, 14:05".
  static String seenAt(DateTime d) {
    final days = _daysAgo(d);
    if (days <= 0) return time(d);
    if (days == 1) return _t.get(Keys.commonYesterdayAt, {'time': time(d)});
    return _t.get(Keys.commonDateAt, {'date': DateFormat.yMd(_locale).format(d), 'time': time(d)});
  }

  /// Uma hora no futuro (ex.: até quando está silenciada): "14:05" se for hoje, senão "18/10, 14:05".
  static String until(DateTime d) {
    final local = d.toLocal();
    final today = BirthdayUtils.today();
    if (DateTime(local.year, local.month, local.day) == today) return time(local);
    return _t.get(Keys.commonDateAt, {'date': DateFormat.MMMd(_locale).format(local), 'time': time(local)});
  }

  /// "Online" ou "Visto por último hoje às 14:05"; `null` se não se souber.
  static String? presence({required bool online, DateTime? lastSeenAt}) {
    if (online) return _t.get(Keys.chatOnline);
    if (lastSeenAt == null) return null;
    final days = _daysAgo(lastSeenAt);
    if (days <= 0) return _t.get(Keys.chatLastSeenToday, {'time': time(lastSeenAt)});
    if (days == 1) return _t.get(Keys.chatLastSeenYesterday, {'time': time(lastSeenAt)});
    return _t.get(Keys.chatLastSeenDate, {'date': DateFormat.yMMMd(_locale).format(lastSeenAt)});
  }

  static String _first(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.first.isEmpty ? name : parts.first;
  }

  /// "Gil está a escrever…", "Gil e Ana estão a escrever…", "3 pessoas estão a escrever…".
  static String typing(Iterable<String> names) {
    final n = names.map(_first).toList();
    return switch (n.length) {
      0 => '',
      1 => _t.get(Keys.chatTypingOne, {'name': n[0]}),
      2 => _t.get(Keys.chatTypingTwo, {'a': n[0], 'b': n[1]}),
      _ => _t.get(Keys.chatTypingMany, {'count': n.length}),
    };
  }

  /// "Vista por Gil", "Vista por Gil e Ana", "Vista por Gil e mais 2", "Vista por todos".
  /// [others] é quantas pessoas (além de mim) podiam ver.
  static String seenBy(List<ChatUser> users, {int? others}) {
    if (users.isEmpty) return '';
    if (others != null && others > 1 && users.length >= others) return _t.get(Keys.chatSeenByEveryone);
    final n = users.map((u) => _first(u.name)).toList();
    return switch (n.length) {
      1 => _t.get(Keys.chatSeenByOne, {'name': n[0]}),
      2 => _t.get(Keys.chatSeenByTwo, {'a': n[0], 'b': n[1]}),
      _ => _t.get(Keys.chatSeenByMany, {'name': n[0], 'count': n.length - 1}),
    };
  }
}
