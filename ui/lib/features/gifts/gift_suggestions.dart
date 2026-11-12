import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/translations.dart';
import '../../data/models/models.dart';

enum GiftTopic {
  books(['livro', 'ler', 'leitura', 'romance', 'banda desenhada']),
  experiences(['viajar', 'viagem', 'aventura', 'concerto', 'teatro', 'música', 'cinema']),
  home(['planta', 'jardim', 'casa', 'decoração', 'vela']),
  food(['cozinha', 'cozinhar', 'vinho', 'chá', 'café', 'chocolate', 'doce', 'receita']),
  wellbeing(['yoga', 'spa', 'desporto', 'correr', 'ginásio', 'relaxar', 'massagem']),
  tech(['jogo', 'jogos', 'tecnologia', 'gadget', 'fotografia', 'computador']),
  style(['moda', 'roupa', 'beleza', 'maquilhagem', 'perfume', 'joias']);

  const GiftTopic(this.keywords);
  final List<String> keywords;

  String get label => switch (this) {
    books => tr('Livros'),
    experiences => tr('Experiências'),
    home => tr('Casa e plantas'),
    food => tr('Gourmet'),
    wellbeing => tr('Bem-estar'),
    tech => tr('Tecnologia'),
    style => tr('Moda e beleza'),
  };
}

class GiftSuggestion {
  const GiftSuggestion(this.title, this.description, this.min, this.max, this.topic, this.icon);

  final String title;
  final String description;
  final int min;
  final int max;
  final GiftTopic topic;
  final IconData icon;

  String get range => '$min\u00a0€\u00a0–\u00a0$max\u00a0€';
}

/// Gostos e hobbies que se escolhem para cada pessoa e no próprio perfil. A
/// chave vai para o servidor; não mudar as existentes.
enum Interest {
  books('books', LucideIcons.bookOpen, GiftTopic.books),
  music('music', LucideIcons.music, GiftTopic.experiences),
  movies('movies', LucideIcons.clapperboard, GiftTopic.experiences),
  travel('travel', LucideIcons.plane, GiftTopic.experiences),
  crafts('crafts', LucideIcons.palette, GiftTopic.experiences),
  cooking('cooking', LucideIcons.chefHat, GiftTopic.food),
  wine('wine', LucideIcons.wine, GiftTopic.food),
  coffeeTea('coffee_tea', LucideIcons.coffee, GiftTopic.food),
  sweets('sweets', LucideIcons.cakeSlice, GiftTopic.food),
  plants('plants', LucideIcons.sprout, GiftTopic.home),
  decor('decor', LucideIcons.sofa, GiftTopic.home),
  animals('animals', LucideIcons.pawPrint, GiftTopic.home),
  sport('sport', LucideIcons.dumbbell, GiftTopic.wellbeing),
  yoga('yoga', LucideIcons.flower2, GiftTopic.wellbeing),
  outdoors('outdoors', LucideIcons.mountain, GiftTopic.wellbeing),
  fashion('fashion', LucideIcons.shirt, GiftTopic.style),
  beauty('beauty', LucideIcons.sparkles, GiftTopic.style),
  tech('tech', LucideIcons.cpu, GiftTopic.tech),
  games('games', LucideIcons.gamepad2, GiftTopic.tech),
  photography('photography', LucideIcons.camera, GiftTopic.tech);

  const Interest(this.key, this.icon, this.topic);
  final String key;
  final IconData icon;
  final GiftTopic topic;

  String get label => switch (this) {
    books => tr('Livros'),
    music => tr('Música'),
    movies => tr('Cinema e séries'),
    travel => tr('Viagens'),
    crafts => tr('Arte e trabalhos manuais'),
    cooking => tr('Cozinhar'),
    wine => tr('Vinho'),
    coffeeTea => tr('Café e chá'),
    sweets => tr('Doces'),
    plants => tr('Plantas'),
    decor => tr('Casa e decoração'),
    animals => tr('Animais'),
    sport => tr('Desporto'),
    yoga => tr('Yoga e meditação'),
    outdoors => tr('Natureza e caminhadas'),
    fashion => tr('Moda'),
    beauty => tr('Beleza e cuidados'),
    tech => tr('Tecnologia'),
    games => tr('Jogos'),
    photography => tr('Fotografia'),
  };

  /// As chaves conhecidas, pela ordem do catálogo (as desconhecidas ficam de fora).
  static List<Interest> fromKeys(Iterable<String> keys) => values.where((i) => keys.contains(i.key)).toList();
}

List<GiftSuggestion> get giftSuggestions => [
  GiftSuggestion(
    tr('Edição ilustrada de um clássico'),
    tr('Capa dura, para ficar na estante.'),
    25,
    40,
    GiftTopic.books,
    LucideIcons.bookOpen,
  ),
  GiftSuggestion(
    tr('Assinatura de livros'),
    tr('Um livro surpresa por mês, durante três meses.'),
    30,
    45,
    GiftTopic.books,
    LucideIcons.libraryBig,
  ),
  GiftSuggestion(
    tr('Leitor de livros digitais'),
    tr('Leve, com luz para ler à noite.'),
    100,
    160,
    GiftTopic.books,
    LucideIcons.tabletSmartphone,
  ),
  GiftSuggestion(
    tr('Workshop de cerâmica'),
    tr('Uma tarde a fazer a própria caneca.'),
    35,
    50,
    GiftTopic.experiences,
    LucideIcons.palette,
  ),
  GiftSuggestion(
    tr('Bilhetes para um concerto'),
    tr('Escolham juntos a data.'),
    30,
    80,
    GiftTopic.experiences,
    LucideIcons.music,
  ),
  GiftSuggestion(
    tr('Escapadinha de fim de semana'),
    tr('Duas noites num sítio por descobrir.'),
    120,
    250,
    GiftTopic.experiences,
    LucideIcons.tentTree,
  ),
  GiftSuggestion(
    tr('Planta grande para a sala'),
    tr('Monstera ou figueira-lira, com vaso.'),
    30,
    60,
    GiftTopic.home,
    LucideIcons.sprout,
  ),
  GiftSuggestion(
    tr('Kit de ervas aromáticas'),
    tr('Para a janela da cozinha.'),
    15,
    25,
    GiftTopic.home,
    LucideIcons.leaf,
  ),
  GiftSuggestion(tr('Vela artesanal'), tr('Cera de soja e um cheiro bom.'), 12, 22, GiftTopic.home, LucideIcons.flame),
  GiftSuggestion(
    tr('Caixa de chás premium'),
    tr('Uma seleção de chás de todo o mundo.'),
    18,
    24,
    GiftTopic.food,
    LucideIcons.coffee,
  ),
  GiftSuggestion(
    tr('Jantar num restaurante novo'),
    tr('Um voucher para dois.'),
    50,
    90,
    GiftTopic.food,
    LucideIcons.utensils,
  ),
  GiftSuggestion(
    tr('Cabaz de produtos portugueses'),
    tr('Queijo, enchidos, doce e vinho.'),
    35,
    60,
    GiftTopic.food,
    LucideIcons.gift,
  ),
  GiftSuggestion(
    tr('Massagem de relaxamento'),
    tr('Uma hora só para si.'),
    45,
    70,
    GiftTopic.wellbeing,
    LucideIcons.flower2,
  ),
  GiftSuggestion(
    tr('Tapete de yoga'),
    tr('Antiderrapante, com bolsa.'),
    25,
    45,
    GiftTopic.wellbeing,
    LucideIcons.heartPulse,
  ),
  GiftSuggestion(
    tr('Garrafa térmica'),
    tr('Mantém a água fresca o dia inteiro.'),
    20,
    35,
    GiftTopic.wellbeing,
    LucideIcons.cupSoda,
  ),
  GiftSuggestion(
    tr('Auriculares sem fios'),
    tr('Para o ginásio ou o comboio.'),
    40,
    120,
    GiftTopic.tech,
    LucideIcons.headphones,
  ),
  GiftSuggestion(
    tr('Lenço de seda'),
    tr('Estampado, para todas as estações.'),
    25,
    45,
    GiftTopic.style,
    LucideIcons.shirt,
  ),
  GiftSuggestion(
    tr('Kit de cuidados de pele'),
    tr('Produtos naturais, feitos cá.'),
    25,
    40,
    GiftTopic.style,
    LucideIcons.sparkles,
  ),
  GiftSuggestion(
    tr('Joia minimalista'),
    tr('Um fio ou uns brincos de prata.'),
    30,
    70,
    GiftTopic.style,
    LucideIcons.gem,
  ),
  GiftSuggestion(
    tr('Jogo de tabuleiro'),
    tr('Para as noites com os amigos.'),
    25,
    45,
    GiftTopic.tech,
    LucideIcons.dices,
  ),
  GiftSuggestion(
    tr('Impressão de fotografias'),
    tr('Um álbum com as melhores do ano.'),
    20,
    40,
    GiftTopic.tech,
    LucideIcons.camera,
  ),
];

/// Os temas que os gostos (da pessoa e, se tiver conta, os que ela própria
/// escolheu em [interests]), as notas e a relação sugerem.
Set<GiftTopic> topicsFor(Person person, {List<String> interests = const []}) {
  final text = '${person.notes} ${person.relation}'.toLowerCase();
  return {
    for (final i in Interest.fromKeys({...person.interests, ...interests})) i.topic,
    for (final t in GiftTopic.values)
      if (t.keywords.any(text.contains)) t,
  };
}

/// As sugestões para [person]: do [topic] escolhido (ou todas), até [maxPrice],
/// primeiro as dos temas que lhe interessam e depois as mais baratas.
/// Com [onlyLiked], só as dos temas que lhe interessam (se houver algum).
List<GiftSuggestion> suggestionsFor(
  Person person, {
  GiftTopic? topic,
  double? maxPrice,
  List<String> interests = const [],
  bool onlyLiked = false,
}) {
  final liked = topicsFor(person, interests: interests);
  return giftSuggestions
      .where((s) => topic == null || s.topic == topic)
      .where((s) => !onlyLiked || liked.isEmpty || liked.contains(s.topic))
      .where((s) => maxPrice == null || s.min <= maxPrice)
      .toList()
    ..sort((a, b) {
      final byTopic = (liked.contains(a.topic) ? 0 : 1).compareTo(liked.contains(b.topic) ? 0 : 1);
      return byTopic != 0 ? byTopic : a.min.compareTo(b.min);
    });
}
