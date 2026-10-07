import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/services/contacts_import.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _contact(
  String name, {
  Map<String, dynamic>? date,
  List<Map<String, dynamic>>? birthdays,
  List<Map<String, dynamic>> photos = const [],
}) => {
  'resourceName': 'people/$name',
  'names': [
    {'displayName': name},
  ],
  'birthdays':
      birthdays ??
      [
        if (date != null) {'date': date},
      ],
  'photos': photos,
};

void main() {
  group('Google Contacts', () {
    test('lê nome, data, ano e fotografia; ignora quem não tem data', () {
      final scan = ContactsImporter.parseGoogleConnections([
        _contact(
          'Rita Lopes',
          date: {'year': 1990, 'month': 3, 'day': 12},
          photos: [
            {'url': 'https://lh3/default', 'default': true},
            {'url': 'https://lh3/rita'},
          ],
        ),
        _contact('Avó Rosa', date: {'month': 12, 'day': 25}),
        _contact('Sem Data'),
        {'resourceName': 'people/x'}, // sem nome
      ]);

      expect(scan.withoutBirthday, 2);
      expect(scan.candidates.map((c) => c.name), ['Avó Rosa', 'Rita Lopes']);
      final rita = scan.candidates.last;
      expect((rita.day, rita.month, rita.year), (12, 3, 1990));
      expect(rita.photoUrl, 'https://lh3/rita');
      expect(scan.candidates.first.year, isNull);
      expect(scan.candidates.first.photoUrl, isNull);
    });

    test('prefere a data principal e a que tem ano', () {
      final scan = ContactsImporter.parseGoogleConnections([
        _contact(
          'João',
          birthdays: [
            {
              'date': {'month': 5, 'day': 1},
            },
            {
              'metadata': {'primary': true},
              'date': {'year': 1985, 'month': 5, 'day': 2},
            },
          ],
        ),
      ]);
      final c = scan.candidates.single;
      expect((c.day, c.month, c.year), (2, 5, 1985));
    });

    test('rejeita datas impossíveis e anos fora do intervalo', () {
      final scan = ContactsImporter.parseGoogleConnections([
        _contact('A', date: {'month': 2, 'day': 30}),
        _contact('B', date: {'month': 13, 'day': 1}),
        _contact('C', date: {'year': 1604, 'month': 2, 'day': 29}),
        _contact('D', date: {'year': 3000, 'month': 4, 'day': 30}),
      ]);
      expect(scan.withoutBirthday, 2);
      expect(scan.candidates.map((c) => (c.name, c.year)), [('C', null), ('D', null)]);
    });

    test('junta repetidos (mesmo nome, ignorando acentos, e mesma data)', () {
      final scan = ContactsImporter.parseGoogleConnections([
        _contact('José Silva', date: {'month': 7, 'day': 4}),
        _contact('jose silva', date: {'month': 7, 'day': 4}),
        _contact('José Silva', date: {'month': 7, 'day': 5}),
      ]);
      expect(scan.candidates, hasLength(2));
    });

    test('lê a página da People API', () {
      final page = GooglePage.parse(
        '{"connections":[{"resourceName":"people/1"}],"nextPageToken":"abc","totalPeople":1}',
      );
      expect(page.connections, hasLength(1));
      expect(page.nextPageToken, 'abc');
      expect(GooglePage.parse('{}').connections, isEmpty);
    });
  });

  test('deteta quem já está na lista', () {
    final existing = [Person(id: '1', name: 'Inês Costa', day: 9, month: 10, createdAt: DateTime(2026))];
    const same = ContactCandidate(key: 'a', name: 'ines costa ', day: 9, month: 10);
    const other = ContactCandidate(key: 'b', name: 'Inês Costa', day: 10, month: 10);
    final keys = ContactCandidate.keysOf(existing);
    expect(same.isIn(keys), isTrue);
    expect(other.isIn(keys), isFalse);

    final person = other.toPerson(categoryId: 'cat');
    expect((person.name, person.day, person.month, person.categoryId), ('Inês Costa', 10, 10, 'cat'));
  });
}
