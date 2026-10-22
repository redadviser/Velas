import '../core/utils/birthday_utils.dart';
import '../data/models/models.dart';

/// Um lembrete pronto a agendar: o texto, para onde leva ao tocar e se tem o
/// botão "Prenda em grupo".
typedef Reminder = ({String title, String body, String payload, bool groupAction});

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
      title: '⏰ Está na hora de dar os parabéns a ${p.firstName}',
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
    final ageText = age == null ? '' : ' Faz $age anos.';
    return switch (daysBefore) {
      0 => (
        title: '🎂 Hoje é o aniversário de ${p.firstName}',
        body: hasMessage
            ? 'A tua mensagem está pronta, toca para a enviar.$ageText'
            : 'Toca para lhe escreveres os parabéns.$ageText',
        payload: 'message:${p.id}',
        groupAction: false,
      ),
      1 => (
        title: '${p.name} faz anos amanhã',
        body: '${Fmt.dayMonth(date)}.$ageText ${hasMessage ? 'A tua mensagem já está pronta.' : 'Já tens a mensagem pronta?'}',
        payload: 'message:${p.id}',
        groupAction: false,
      ),
      _ => (
        title: '${p.name} faz anos daqui a ${reminderShortLabel(daysBefore)}',
        body:
            '${Fmt.weekdayDayMonth(date)}.$ageText ${switch (ideas) {
              0 => 'Ainda vais a tempo de tratar do presente.',
              1 => 'Tens 1 ideia de presente guardada.',
              _ => 'Tens $ideas ideias de presente guardadas.',
            }}',
        payload: 'person:${p.id}',
        groupAction: daysBefore >= _groupMinDays,
      ),
    };
  }

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
      'agenda' => '/agenda',
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
    final names = [
      for (final (d, p) in week.take(4)) '${p.firstName} (${Fmt.weekdayShort(d).toLowerCase()})',
    ];
    final more = week.length - names.length;
    return (
      title: week.length == 1 ? '🎂 Esta semana faz anos 1 pessoa' : '🎂 Esta semana fazem anos ${week.length} pessoas',
      body: more > 0 ? '${names.join(', ')} e mais $more.' : '${names.join(', ')}.',
      payload: 'agenda:week',
    );
  }
}
