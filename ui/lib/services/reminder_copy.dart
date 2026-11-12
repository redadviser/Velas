import '../core/i18n/translations.dart';
import '../core/utils/birthday_utils.dart';
import '../data/models/models.dart';

/// Um lembrete pronto a agendar: o texto, para onde leva ao tocar e se tem o
/// botão "Prenda em grupo".
typedef Reminder = ({String title, String body, String payload, bool groupAction});

/// Um lembrete por agendar: quando, de quem (pessoa ou data especial) e de que dia.
typedef PlannedReminder = ({DateTime when, Person? person, SpecialDate? special, int daysBefore, DateTime occurrence});

/// O texto e o destino de cada lembrete dependem de quanto falta: perto do
/// dia leva aos parabéns; com tempo, à pessoa (ideias de presente) e, pelo
/// botão, à prenda em grupo.
class ReminderCopy {
  const ReminderCopy._();

  /// Ação do botão "Prenda em grupo" (ver [target]).
  static const groupAction = 'group';

  /// Mensagem agendada para enviar fora da app: chegou a hora. Tocar abre a
  /// mensagem já com o "Como queres enviar?" aberto.
  static Reminder scheduledSend(Person p, BirthdayMessage m) {
    final text = m.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return (
      title: tr('⏰ Está na hora de dar os parabéns a {name}', {'name': p.firstName}),
      body: text.length > 120 ? '${text.substring(0, 120)}…' : text,
      payload: 'send:${p.id}',
      groupAction: false,
    );
  }

  /// Com menos de 3 dias já não dá para combinar uma prenda em grupo.
  static const _groupMinDays = 3;

  static Reminder build(
    Person p, {
    required int daysBefore,
    required DateTime date,
    int? age,
    bool hasMessage = false,
    int ideas = 0,
  }) {
    final ageText = age == null ? '' : ' ${tr('Faz {age} anos.', {'age': age})}';
    return switch (daysBefore) {
      0 => (
        title: tr('🎂 Hoje é o aniversário de {name}', {'name': p.firstName}),
        body:
            (hasMessage
                ? tr('A tua mensagem está pronta, toca para a enviar.')
                : tr('Toca para lhe escreveres os parabéns.')) +
            ageText,
        payload: 'message:${p.id}',
        groupAction: false,
      ),
      1 => (
        title: tr('{name} faz anos amanhã', {'name': p.name}),
        body:
            '${Fmt.dayMonth(date)}.$ageText ${hasMessage ? tr('A tua mensagem já está pronta.') : tr('Já tens a mensagem pronta?')}',
        payload: 'message:${p.id}',
        groupAction: false,
      ),
      _ => (
        title: tr('{name} faz anos daqui a {when}', {'name': p.name, 'when': reminderShortLabel(daysBefore)}),
        body:
            '${Fmt.weekdayDayMonth(date)}.$ageText ${switch (ideas) {
              0 => tr('Ainda vais a tempo de tratar do presente.'),
              1 => tr('Tens 1 ideia de presente guardada.'),
              _ => tr('Tens {count} ideias de presente guardadas.', {'count': ideas}),
            }}',
        payload: 'person:${p.id}',
        groupAction: daysBefore >= _groupMinDays,
      ),
    };
  }

  /// Data especial (casamento, Dia da Mãe…): tocar abre a lista das datas.
  static Reminder special(SpecialDate d, {required int daysBefore, required DateTime date, int? years}) {
    final yearsText = years == null || years <= 0
        ? ''
        : ' ${years == 1 ? tr('Faz 1 ano') : tr('Fazem {years} anos', {'years': years})}.';
    return switch (daysBefore) {
      0 => (
        title: tr('Hoje: {title}', {'title': d.title}),
        body: tr('Um dia para assinalar.') + yearsText,
        payload: 'special:${d.id}',
        groupAction: false,
      ),
      1 => (
        title: tr('{title} é amanhã', {'title': d.title}),
        body: '${Fmt.dayMonth(date)}.$yearsText',
        payload: 'special:${d.id}',
        groupAction: false,
      ),
      _ => (
        title: tr('{title} daqui a {when}', {'title': d.title, 'when': reminderShortLabel(daysBefore)}),
        body: '${Fmt.weekdayDayMonth(date)}.$yearsText',
        payload: 'special:${d.id}',
        groupAction: false,
      ),
    };
  }

  /// Todos os lembretes depois de [now], por ordem (este ano e o seguinte,
  /// para os que já passaram). Usado pelo agendador e pelo ecrã Notificações.
  static List<PlannedReminder> plan(AppData data, UserProfile profile, DateTime now) {
    final out = <PlannedReminder>[];
    void add(int day, int month, List<int> offsets, int hour, int minute, {Person? person, SpecialDate? special}) {
      final next = BirthdayUtils.nextOccurrence(day, month, from: now);
      for (final occurrence in [next, BirthdayUtils.occurrenceIn(next.year + 1, day, month)]) {
        for (final days in offsets) {
          final d = BirthdayUtils.addDays(occurrence, -days);
          final when = DateTime(d.year, d.month, d.day, hour, minute);
          if (when.isAfter(now)) {
            out.add((when: when, person: person, special: special, daysBefore: days, occurrence: occurrence));
          }
        }
      }
    }

    for (final p in data.people) {
      // Hora própria da pessoa (Birthdayly+); senão a do perfil.
      final custom = profile.isPlus && p.reminderHour != null && p.reminderMinute != null;
      add(
        p.day,
        p.month,
        p.reminderDays ?? profile.defaultReminderDays,
        custom ? p.reminderHour! : profile.reminderHour,
        custom ? p.reminderMinute! : profile.reminderMinute,
        person: p,
      );
    }
    for (final s in data.specialDates) {
      add(
        s.day,
        s.month,
        s.reminderDays ?? profile.defaultReminderDays,
        profile.reminderHour,
        profile.reminderMinute,
        special: s,
      );
    }
    return out..sort((a, b) => a.when.compareTo(b.when));
  }

  /// O texto de um lembrete planeado.
  static Reminder copyFor(PlannedReminder p, AppData data) => switch ((p.person, p.special)) {
    (final person?, _) => build(
      person,
      daysBefore: p.daysBefore,
      date: p.occurrence,
      age: person.year == null ? null : p.occurrence.year - person.year!,
      hasMessage: data.messageFor(person.id) != null,
      ideas: data.giftsFor(person.id).where((g) => !g.purchased).length,
    ),
    (_, final s?) => special(
      s,
      daysBefore: p.daysBefore,
      date: p.occurrence,
      years: s.year == null ? null : p.occurrence.year - s.year!,
    ),
    _ => throw StateError('lembrete sem pessoa nem data'),
  };

  /// Para onde leva uma notificação tocada: o botão "Prenda em grupo" muda o
  /// destino de `person:<id>` para `group:<id>`.
  static String? target(String? payload, String? actionId) {
    if (payload == null) return null;
    if (actionId == groupAction && payload.startsWith('person:')) return 'group:${payload.substring(7)}';
    // Notificações de mensagens: `chat:<id>|<token de resposta>` (o token não é destino).
    final bar = payload.indexOf('|');
    return bar < 0 ? payload : payload.substring(0, bar);
  }

  /// Rota da app para um destino (`chat:`, `person:`, `message:`, `group:`).
  /// Os lembretes agendados por versões antigas levam só o id da pessoa.
  static String? route(String payload) {
    final i = payload.indexOf(':');
    final kind = i < 0 ? 'person' : payload.substring(0, i);
    final id = i < 0 ? payload : payload.substring(i + 1);
    if (id.isEmpty) return null;
    return switch (kind) {
      'chat' => '/chats/$id',
      'person' => '/person/$id',
      'message' => '/person/$id/message',
      'send' => '/person/$id/message?send=1',
      'group' => '/groups/new?personId=$id',
      'agenda' => '/people',
      'special' => '/special',
      'wall' => '/wall',
      _ => null,
    };
  }

  /// Resumo semanal (Birthdayly+): os aniversários da semana que começa em
  /// [monday], por ordem. `null` se não houver nenhum (não se manda nada).
  static ({String title, String body, String payload})? weeklyDigest(List<Person> people, DateTime monday) {
    final start = DateTime(monday.year, monday.month, monday.day);
    final week = <(DateTime, Person)>[];
    for (final p in people) {
      final next = BirthdayUtils.nextOccurrence(p.day, p.month, from: start);
      if (next.difference(start).inDays < 7) week.add((next, p));
    }
    if (week.isEmpty) return null;
    week.sort((a, b) => a.$1.compareTo(b.$1));
    final names = [for (final (d, p) in week.take(4)) '${p.firstName} (${Fmt.weekdayShort(d).toLowerCase()})'];
    final more = week.length - names.length;
    return (
      title: week.length == 1
          ? tr('🎂 Esta semana faz anos 1 pessoa')
          : tr('🎂 Esta semana fazem anos {count} pessoas', {'count': week.length}),
      body: more > 0
          ? tr('{names} e mais {count}.', {'names': names.join(', '), 'count': more})
          : '${names.join(', ')}.',
      payload: 'agenda:week',
    );
  }
}
