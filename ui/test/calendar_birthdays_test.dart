import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/features/people/calendar_birthdays.dart';
import 'package:aniversarios/features/people/import_contacts_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconhece o nome nos títulos de aniversário, em várias línguas', () {
    expect(birthdayNameFromTitle('Aniversário da Ana'), 'Ana');
    expect(birthdayNameFromTitle('Aniversário de Rui Gomes'), 'Rui Gomes');
    expect(birthdayNameFromTitle('aniversario do Pai'), 'Pai');
    expect(birthdayNameFromTitle('🎂 Parabéns Tia Rosa'), 'Tia Rosa');
    expect(birthdayNameFromTitle('Ana Silva - aniversário'), 'Ana Silva');
    expect(birthdayNameFromTitle('Zé faz anos'), 'Zé');
    expect(birthdayNameFromTitle("Ana's birthday"), 'Ana');
    expect(birthdayNameFromTitle('Rui’s Birthday'), 'Rui');
    expect(birthdayNameFromTitle('Birthday: Tom'), 'Tom');
    expect(birthdayNameFromTitle('Cumpleaños de María'), 'María');
    expect(birthdayNameFromTitle('Anniversaire de Léa'), 'Léa');
    expect(birthdayNameFromTitle('Aniversário da Ana (30)'), 'Ana');
    // Não são aniversários.
    expect(birthdayNameFromTitle('Reunião de equipa'), isNull);
    expect(birthdayNameFromTitle('Aniversário'), isNull);
    expect(birthdayNameFromTitle('Dentista'), isNull);
  });

  test('junta os calendários de aniversários e os eventos com título de aniversário', () {
    final found = calendarBirthdays([
      (id: '1', title: 'Aniversário da Ana', start: DateTime(2026, 11, 3), calendarName: 'eu@gmail.com'),
      // No calendário "Aniversários" o título pode ser só o nome.
      (id: '2', title: 'Rui Gomes', start: DateTime(2027, 2, 14), calendarName: 'Aniversários'),
      (id: '3', title: "Bea's birthday", start: DateTime(2027, 1, 9), calendarName: 'Birthdays'),
      (id: '4', title: 'Reunião', start: DateTime(2026, 11, 4), calendarName: 'eu@gmail.com'),
    ]);
    expect(found.map((e) => (e.name, e.date)), [
      ('Ana', (day: 3, month: 11, year: null)),
      ('Rui Gomes', (day: 14, month: 2, year: null)),
      ('Bea', (day: 9, month: 1, year: null)),
    ]);
    // Quem já está na lista não aparece outra vez.
    final ana = Person(id: 'p', name: 'ana', day: 3, month: 11, createdAt: DateTime(2026));
    expect(newContacts(found, [ana]).map((e) => e.name), ['Bea', 'Rui Gomes']);
  });
}
