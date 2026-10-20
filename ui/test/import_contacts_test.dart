import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/features/people/birthday_picker.dart';
import 'package:aniversarios/features/people/import_contacts_screen.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_test/flutter_test.dart';

Contact contact(String name, {List<Event> events = const []}) => Contact(id: name, displayName: name, events: events);

void main() {
  test('só conta o aniversário, e um ano impossível fica sem ano', () {
    expect(birthdayOf(contact('Sem data')), isNull);
    expect(
      birthdayOf(contact('Casamento', events: [const Event(year: 2010, month: 6, day: 1, label: Label(EventLabel.anniversary))])),
      isNull,
    );
    expect(
      birthdayOf(contact('Ana', events: [const Event(year: 1990, month: 5, day: 3, label: Label(EventLabel.birthday))])),
      (day: 3, month: 5, year: 1990),
    );
    // O iPhone usa 1604 para "sem ano".
    expect(
      birthdayOf(contact('Rui', events: [const Event(year: 1604, month: 1, day: 9, label: Label(EventLabel.birthday))])),
      (day: 9, month: 1, year: null),
    );
  });

  test('aceita a etiqueta personalizada "Aniversário" e as linhas originais do Android', () {
    expect(
      birthdayOf(contact('Bea', events: [const Event(month: 2, day: 14, label: Label(EventLabel.custom, 'Aniversário'))])),
      (day: 14, month: 2, year: null),
    );

    // O plugin rejeita "03/05/1990"; a linha original (tipo 3 = aniversário) é lida aqui.
    const raw = AndroidData(
      debugData: {
        'vnd.android.cursor.item/contact_event': [
          {'data1': '01/01/2000', 'data2': 1}, // aniversário de casamento: ignorado
          {'data1': '03/05/1990', 'data2': 3},
        ],
      },
    );
    expect(birthdayOf(const Contact(id: 'x', displayName: 'Rui', android: raw)), (day: 3, month: 5, year: 1990));
  });

  test('lê as datas como as apps de contactos as gravam', () {
    expect(parseContactDate('1990-05-03'), (year: 1990, month: 5, day: 3));
    expect(parseContactDate('19900503'), (year: 1990, month: 5, day: 3));
    expect(parseContactDate('--05-03'), (year: null, month: 5, day: 3));
    expect(parseContactDate('03/05/1990'), (year: 1990, month: 5, day: 3));
    expect(parseContactDate('3.5.1990'), (year: 1990, month: 5, day: 3));
    expect(parseContactDate('03/05'), (year: null, month: 5, day: 3));
    expect(parseContactDate('1990-05-03T00:00:00Z'), (year: 1990, month: 5, day: 3));
    expect(parseContactDate('maio'), isNull);
  });

  test('mostra todos os contactos que faltam, sem repetidos (fica o que tem data)', () {
    expect(entryOf(contact('   ')), isNull);
    expect(entryOf(contact('Sem data'))!.date, isNull);

    ContactEntry e(String name, [BirthDate? date]) => (key: name, name: name, photo: null, date: date);
    final existing = [Person(id: 'p1', name: 'Ana Silva', day: 3, month: 5, createdAt: DateTime(2026))];
    final fresh = newContacts([
      e('rui gomes'),
      e('ANA SILVA'), // já está na lista
      e('Bea', (day: 1, month: 2, year: null)),
      e('Rui Gomes', (day: 9, month: 1, year: null)), // repetido: fica este, que tem data
    ], existing);
    expect(fresh.map((c) => (c.name, c.date?.day)), [('Bea', 1), ('Rui Gomes', 9)]);
  });
}
