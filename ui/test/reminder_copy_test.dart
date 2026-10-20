import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/services/reminder_copy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  final ana = Person(id: 'p1', name: 'Ana Silva', day: 3, month: 5, createdAt: DateTime(2026));
  final date = DateTime(2027, 5, 3);

  test('no dia e na véspera leva aos parabéns, sem botão de prenda em grupo', () {
    final today = ReminderCopy.build(ana, daysBefore: 0, date: date, age: 30, hasMessage: true);
    expect(today.title, '🎂 Hoje é o aniversário de Ana');
    expect(today.body, 'A tua mensagem está pronta, toca para a enviar. Faz 30 anos.');
    expect(today.payload, 'message:p1');
    expect(today.groupAction, isFalse);

    final tomorrow = ReminderCopy.build(ana, daysBefore: 1, date: date);
    expect(tomorrow.body, endsWith('Já tens a mensagem pronta?'));
    expect(tomorrow.payload, 'message:p1');
  });

  test('com tempo leva à pessoa, fala das ideias guardadas e oferece a prenda em grupo', () {
    final week = ReminderCopy.build(ana, daysBefore: 7, date: date, ideas: 2);
    expect(week.payload, 'person:p1');
    expect(week.body, endsWith('Tens 2 ideias de presente guardadas.'));
    expect(week.groupAction, isTrue);
    // A 2 dias já não dá para combinar a prenda em grupo.
    expect(ReminderCopy.build(ana, daysBefore: 2, date: date).groupAction, isFalse);
  });

  test('o botão muda o destino e cada destino tem a sua rota', () {
    expect(ReminderCopy.target('person:p1', ReminderCopy.groupAction), 'group:p1');
    expect(ReminderCopy.target('person:p1', null), 'person:p1');
    expect(ReminderCopy.target('chat:c1', ReminderCopy.groupAction), 'chat:c1');
    expect(ReminderCopy.target(null, null), isNull);

    expect(ReminderCopy.route('chat:c1'), '/chats/c1');
    expect(ReminderCopy.route('person:p1'), '/person/p1');
    expect(ReminderCopy.route('message:p1'), '/person/p1/message');
    expect(ReminderCopy.route('group:p1'), '/groups/new?personId=p1');
    // Lembretes agendados por versões antigas: só o id da pessoa.
    expect(ReminderCopy.route('3f2a9c1e-5b7d-4e8a-9c21-7d4e5f6a8b90'), '/person/3f2a9c1e-5b7d-4e8a-9c21-7d4e5f6a8b90');
    expect(ReminderCopy.route('outra:coisa'), isNull);
  });
}
