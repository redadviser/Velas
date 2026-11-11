import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/models/models.dart';

enum GiftTopic {
  books('Livros', ['livro', 'ler', 'leitura', 'romance', 'banda desenhada']),
  experiences('Experiências', ['viajar', 'viagem', 'aventura', 'concerto', 'teatro', 'música', 'cinema']),
  home('Casa e plantas', ['planta', 'jardim', 'casa', 'decoração', 'vela']),
  food('Gourmet', ['cozinha', 'cozinhar', 'vinho', 'chá', 'café', 'chocolate', 'doce', 'receita']),
  wellbeing('Bem-estar', ['yoga', 'spa', 'desporto', 'correr', 'ginásio', 'relaxar', 'massagem']),
  tech('Tecnologia', ['jogo', 'jogos', 'tecnologia', 'gadget', 'fotografia', 'computador']),
  style('Moda e beleza', ['moda', 'roupa', 'beleza', 'maquilhagem', 'perfume', 'joias']);

  const GiftTopic(this.label, this.keywords);
  final String label;
  final List<String> keywords;
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
  books('books', 'Livros', LucideIcons.bookOpen, GiftTopic.books),
  music('music', 'Música', LucideIcons.music, GiftTopic.experiences),
  movies('movies', 'Cinema e séries', LucideIcons.clapperboard, GiftTopic.experiences),
  travel('travel', 'Viagens', LucideIcons.plane, GiftTopic.experiences),
  crafts('crafts', 'Arte e trabalhos manuais', LucideIcons.palette, GiftTopic.experiences),
  cooking('cooking', 'Cozinhar', LucideIcons.chefHat, GiftTopic.food),
  wine('wine', 'Vinho', LucideIcons.wine, GiftTopic.food),
  coffeeTea('coffee_tea', 'Café e chá', LucideIcons.coffee, GiftTopic.food),
  sweets('sweets', 'Doces', LucideIcons.cakeSlice, GiftTopic.food),
  plants('plants', 'Plantas', LucideIcons.sprout, GiftTopic.home),
  decor('decor', 'Casa e decoração', LucideIcons.sofa, GiftTopic.home),
  animals('animals', 'Animais', LucideIcons.pawPrint, GiftTopic.home),
  sport('sport', 'Desporto', LucideIcons.dumbbell, GiftTopic.wellbeing),
  yoga('yoga', 'Yoga e meditação', LucideIcons.flower2, GiftTopic.wellbeing),
  outdoors('outdoors', 'Natureza e caminhadas', LucideIcons.mountain, GiftTopic.wellbeing),
  fashion('fashion', 'Moda', LucideIcons.shirt, GiftTopic.style),
  beauty('beauty', 'Beleza e cuidados', LucideIcons.sparkles, GiftTopic.style),
  tech('tech', 'Tecnologia', LucideIcons.cpu, GiftTopic.tech),
  games('games', 'Jogos', LucideIcons.gamepad2, GiftTopic.tech),
  photography('photography', 'Fotografia', LucideIcons.camera, GiftTopic.tech);

  const Interest(this.key, this.label, this.icon, this.topic);
  final String key;
  final String label;
  final IconData icon;
  final GiftTopic topic;

  /// As chaves conhecidas, pela ordem do catálogo (as desconhecidas ficam de fora).
  static List<Interest> fromKeys(Iterable<String> keys) => values.where((i) => keys.contains(i.key)).toList();
}

const giftSuggestions = [
  GiftSuggestion(
    'Edição ilustrada de um clássico',
    'Capa dura, para ficar na estante.',
    25,
    40,
    GiftTopic.books,
    LucideIcons.bookOpen,
  ),
  GiftSuggestion(
    'Assinatura de livros',
    'Um livro surpresa por mês, durante três meses.',
    30,
    45,
    GiftTopic.books,
    LucideIcons.libraryBig,
  ),
  GiftSuggestion(
    'Leitor de livros digitais',
    'Leve, com luz para ler à noite.',
    100,
    160,
    GiftTopic.books,
    LucideIcons.tabletSmartphone,
  ),
  GiftSuggestion(
    'Workshop de cerâmica',
    'Uma tarde a fazer a própria caneca.',
    35,
    50,
    GiftTopic.experiences,
    LucideIcons.palette,
  ),
  GiftSuggestion(
    'Bilhetes para um concerto',
    'Escolham juntos a data.',
    30,
    80,
    GiftTopic.experiences,
    LucideIcons.music,
  ),
  GiftSuggestion(
    'Escapadinha de fim de semana',
    'Duas noites num sítio por descobrir.',
    120,
    250,
    GiftTopic.experiences,
    LucideIcons.tentTree,
  ),
  GiftSuggestion(
    'Planta grande para a sala',
    'Monstera ou figueira-lira, com vaso.',
    30,
    60,
    GiftTopic.home,
    LucideIcons.sprout,
  ),
  GiftSuggestion('Kit de ervas aromáticas', 'Para a janela da cozinha.', 15, 25, GiftTopic.home, LucideIcons.leaf),
  GiftSuggestion('Vela artesanal', 'Cera de soja e um cheiro bom.', 12, 22, GiftTopic.home, LucideIcons.flame),
  GiftSuggestion(
    'Caixa de chás premium',
    'Uma seleção de chás de todo o mundo.',
    18,
    24,
    GiftTopic.food,
    LucideIcons.coffee,
  ),
  GiftSuggestion('Jantar num restaurante novo', 'Um voucher para dois.', 50, 90, GiftTopic.food, LucideIcons.utensils),
  GiftSuggestion(
    'Cabaz de produtos portugueses',
    'Queijo, enchidos, doce e vinho.',
    35,
    60,
    GiftTopic.food,
    LucideIcons.gift,
  ),
  GiftSuggestion('Massagem de relaxamento', 'Uma hora só para si.', 45, 70, GiftTopic.wellbeing, LucideIcons.flower2),
  GiftSuggestion('Tapete de yoga', 'Antiderrapante, com bolsa.', 25, 45, GiftTopic.wellbeing, LucideIcons.heartPulse),
  GiftSuggestion(
    'Garrafa térmica',
    'Mantém a água fresca o dia inteiro.',
    20,
    35,
    GiftTopic.wellbeing,
    LucideIcons.cupSoda,
  ),
  GiftSuggestion(
    'Auriculares sem fios',
    'Para o ginásio ou o comboio.',
    40,
    120,
    GiftTopic.tech,
    LucideIcons.headphones,
  ),
  GiftSuggestion('Lenço de seda', 'Estampado, para todas as estações.', 25, 45, GiftTopic.style, LucideIcons.shirt),
  GiftSuggestion(
    'Kit de cuidados de pele',
    'Produtos naturais, feitos cá.',
    25,
    40,
    GiftTopic.style,
    LucideIcons.sparkles,
  ),
  GiftSuggestion('Joia minimalista', 'Um fio ou uns brincos de prata.', 30, 70, GiftTopic.style, LucideIcons.gem),
  GiftSuggestion('Jogo de tabuleiro', 'Para as noites com os amigos.', 25, 45, GiftTopic.tech, LucideIcons.dices),
  GiftSuggestion(
    'Impressão de fotografias',
    'Um álbum com as melhores do ano.',
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
