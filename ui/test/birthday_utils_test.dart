import 'package:aniversarios/core/utils/birthday_utils.dart';
import 'package:aniversarios/data/local/default_data.dart';
import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/services/message_suggestions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  group('BirthdayUtils', () {
    test('próxima ocorrência ainda este ano', () {
      final from = DateTime(2026, 3, 10);
      expect(BirthdayUtils.nextOccurrence(20, 3, from: from), DateTime(2026, 3, 20));
      expect(BirthdayUtils.daysUntil(20, 3, from: from), 10);
    });

    test('aniversário hoje conta como 0 dias', () {
      final from = DateTime(2026, 10, 6);
      expect(BirthdayUtils.daysUntil(6, 10, from: from), 0);
    });

    test('aniversário já passou passa para o ano seguinte', () {
      final from = DateTime(2026, 10, 6);
      expect(BirthdayUtils.nextOccurrence(5, 10, from: from), DateTime(2027, 10, 5));
      expect(BirthdayUtils.daysUntil(5, 10, from: from), 364);
    });

    test('29 de fevereiro celebra-se a 28 em anos não bissextos', () {
      expect(BirthdayUtils.occurrenceIn(2027, 29, 2), DateTime(2027, 2, 28));
      expect(BirthdayUtils.occurrenceIn(2028, 29, 2), DateTime(2028, 2, 29));
      expect(BirthdayUtils.nextOccurrence(29, 2, from: DateTime(2026, 3, 1)), DateTime(2027, 2, 28));
    });

    test('contagem de dias não é afetada pela mudança de hora', () {
      // Em Portugal a hora muda no último domingo de outubro.
      expect(BirthdayUtils.daysUntil(1, 11, from: DateTime(2026, 10, 20)), 12);
      expect(BirthdayUtils.daysUntil(1, 4, from: DateTime(2026, 3, 20)), 12);
    });

    test('somar dias atravessa a mudança de hora sem perder um dia', () {
      expect(BirthdayUtils.addDays(DateTime(2026, 10, 20), 6), DateTime(2026, 10, 26));
      expect(BirthdayUtils.addDays(DateTime(2027, 2, 28), 1), DateTime(2027, 3, 1));
    });

    test('dias em fevereiro sem ano conhecido permite 29', () {
      expect(BirthdayUtils.daysInMonth(2), 29);
      expect(BirthdayUtils.daysInMonth(2, 2027), 28);
      expect(BirthdayUtils.daysInMonth(4, 2027), 30);
    });
  });

  group('Person', () {
    final today = BirthdayUtils.today();

    test('idade que vai fazer e idade atual', () {
      final tomorrow = today.add(const Duration(days: 1));
      final p = Person(
        id: '1',
        name: 'Ana Silva',
        day: tomorrow.day,
        month: tomorrow.month,
        year: tomorrow.year - 30,
        createdAt: today,
      );
      expect(p.turningAge, 30);
      expect(p.currentAge, 29);
      expect(p.initials, 'AS');
      expect(p.firstName, 'Ana');
    });

    test('sem ano não calcula idade', () {
      final p = Person(id: '1', name: 'João', day: 1, month: 1, createdAt: today);
      expect(p.turningAge, isNull);
      expect(p.initials, 'J');
    });

    test('serialização JSON preserva os campos', () {
      final p = Person(
        id: 'x',
        name: 'Rita',
        day: 3,
        month: 5,
        year: 1990,
        relation: 'Amiga',
        categoryId: 'c1',
        notes: 'gosta de chá',
        giftBudget: 25.5,
        reminderDays: const [0, 7],
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final back = Person.fromJson(p.toJson());
      expect(back.name, 'Rita');
      expect(back.year, 1990);
      expect(back.giftBudget, 25.5);
      expect(back.reminderDays, [0, 7]);
      expect(back.categoryId, 'c1');
    });
  });

  test('conta nova começa sem pessoas e com as categorias por defeito', () {
    final data = DefaultData.initial();
    expect(data.people, isEmpty);
    expect(data.categories.map((c) => c.name), ['Família', 'Amigos', 'Trabalho']);
  });

  test('sugestões incluem o nome da pessoa em todos os tons', () {
    final p = Person(
      id: '1',
      name: 'Marta Reis',
      day: 1,
      month: 1,
      year: 1990,
      relation: 'Mãe',
      createdAt: DateTime.now(),
    );
    for (final tone in MessageTone.values) {
      final s = MessageSuggestions.generate(p, tone);
      expect(s, isNotEmpty);
      expect(s.every((m) => m.contains('Marta')), isTrue);
    }
  });

  test('formatação em português', () {
    expect(Fmt.dayMonth(DateTime(2026, 10, 6)), '6 de outubro');
    expect(Fmt.monthShort(10), 'OUT');
    expect(Fmt.weekdayDayMonth(DateTime(2026, 10, 6)), 'Terça-feira, 6 de outubro');
  });
}
