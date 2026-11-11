import 'package:aniversarios/data/models/models.dart';
import 'package:aniversarios/features/gifts/gift_suggestions.dart';
import 'package:flutter_test/flutter_test.dart';

Person _p({String notes = '', String relation = '', List<String> interests = const []}) => Person(
  id: 'p',
  name: 'Maria',
  day: 1,
  month: 1,
  notes: notes,
  relation: relation,
  interests: interests,
  createdAt: DateTime(2026),
);

void main() {
  test('as notas da pessoa põem os temas dela primeiro', () {
    final list = suggestionsFor(_p(notes: 'Adora Livros e cozinhar.'));
    final firstTopics = list.take(6).map((s) => s.topic).toSet();
    expect(firstTopics, {GiftTopic.books, GiftTopic.food});
    expect(list.length, giftSuggestions.length);
  });

  test('sem notas, das mais baratas para as mais caras', () {
    final mins = suggestionsFor(_p()).map((s) => s.min).toList();
    expect(mins, [...mins]..sort());
  });

  test('tema e orçamento filtram', () {
    final list = suggestionsFor(_p(), topic: GiftTopic.experiences, maxPrice: 40);
    expect(list, isNotEmpty);
    expect(list.every((s) => s.topic == GiftTopic.experiences && s.min <= 40), isTrue);
  });

  test('os gostos da pessoa e os que ela escolheu contam; "só gostos" filtra', () {
    final p = _p(interests: ['wine', 'unknown_key']);
    expect(topicsFor(p, interests: ['yoga']), {GiftTopic.food, GiftTopic.wellbeing});
    final only = suggestionsFor(p, interests: ['yoga'], onlyLiked: true);
    expect(only, isNotEmpty);
    expect(only.every((s) => s.topic == GiftTopic.food || s.topic == GiftTopic.wellbeing), isTrue);
    // Sem gostos nenhuns, "só gostos" não esconde tudo.
    expect(suggestionsFor(_p(), onlyLiked: true).length, giftSuggestions.length);
  });

  test('as chaves dos gostos cabem no que o servidor aceita', () {
    final valid = RegExp(r'^[a-z][a-z_]{1,30}$');
    expect(Interest.values.map((i) => i.key).where((k) => !valid.hasMatch(k)), isEmpty);
    expect(Interest.values.map((i) => i.key).toSet().length, Interest.values.length);
  });
}
