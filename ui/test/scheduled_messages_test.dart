import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/features/messages/schedule_sheet.dart';
import 'package:aniversarios/services/notification_service.dart';
import 'package:aniversarios/services/reminder_copy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  final ana = Person(id: 'p1', name: 'Ana Silva', day: 2, month: 3, createdAt: DateTime(2026));

  test('a mensagem agendada vai e vem no JSON; mudar o agendamento volta a pô-la por enviar', () {
    final at = DateTime(2027, 3, 2, 9);
    final m = BirthdayMessage(
      id: 'm1',
      personId: 'p1',
      body: 'Parabéns!',
      updatedAt: DateTime(2026),
    ).copyWith(schedule: () => (at: at, via: ScheduleVia.wall, friendId: 'u2', mediaKey: null));
    final back = BirthdayMessage.fromJson(m.toJson());
    expect((back.scheduledAt, back.scheduleVia, back.scheduleFriendId), (at, ScheduleVia.wall, 'u2'));
    expect(back.isPending, isTrue);

    final sent = BirthdayMessage.fromJson({...m.toJson(), 'sent_at': '2027-03-02T09:00:30Z'});
    expect(sent.isPending, isFalse);
    // Só mudar o texto mantém o "enviada"; cancelar tira tudo.
    expect(sent.copyWith(body: 'Outro').sentAt, isNotNull);
    final cancelled = sent.copyWith(schedule: () => null);
    expect((cancelled.isScheduled, cancelled.sentAt), (false, null));
  });

  test('por omissão agenda para as 9h do próximo aniversário (ou daqui a pouco, se já passou)', () {
    expect(defaultScheduleTime(ana, DateTime(2026, 10, 22, 15)), DateTime(2027, 3, 2, 9));
    // No próprio dia, depois das 9h: daqui a ~20 minutos, em múltiplos de 5.
    expect(defaultScheduleTime(ana, DateTime(2027, 3, 2, 14, 3)), DateTime(2027, 3, 2, 14, 20));
  });

  test('a notificação de mensagem leva a conversa e o token de resposta, que não é destino', () {
    expect(chatPayloadOf('chat:c1|tok.en'), (conversationId: 'c1', token: 'tok.en'));
    expect(chatPayloadOf('chat:c1'), (conversationId: 'c1', token: null));
    expect(chatPayloadOf('person:p1'), isNull);
    expect(ReminderCopy.target('chat:c1|tok.en', null), 'chat:c1');
    expect(ReminderCopy.route('chat:c1'), '/chats/c1');
  });

  test('o aviso do "lembrar-me" abre a mensagem pronta a enviar', () {
    final m = BirthdayMessage(id: 'm1', personId: 'p1', body: 'Parabéns,\n Ana!', updatedAt: DateTime(2026));
    final r = ReminderCopy.scheduledSend(ana, m);
    expect(r.title, '⏰ Está na hora de dar os parabéns a Ana');
    expect(r.body, 'Parabéns, Ana!');
    expect(ReminderCopy.route(r.payload), '/person/p1/message?send=1');
  });
}
