import '../data/models/models.dart';

enum MessageTone {
  warm('Carinhosa'),
  fun('Divertida'),
  formal('Formal'),
  short('Curta');

  const MessageTone(this.label);
  final String label;
}

/// Sugestões de mensagens de aniversário (RF15), adaptadas ao tom, à idade
/// e à relação com a pessoa. Funciona offline e sem custos de API.
class MessageSuggestions {
  const MessageSuggestions._();

  static const _family = [
    'mãe',
    'pai',
    'avó',
    'avô',
    'irmã',
    'irmão',
    'tia',
    'tio',
    'prima',
    'primo',
    'filha',
    'filho',
    'madrinha',
    'padrinho',
    'afilhada',
    'afilhado',
  ];

  static List<String> generate(Person person, MessageTone tone) {
    final name = person.firstName;
    final age = person.turningAge;
    final rel = person.relation.trim().toLowerCase();
    final isFamily = _family.any(rel.contains);
    final ageWarm = age == null ? '' : ' $age anos!';
    final ageFun = age == null ? 'mais uma volta ao sol' : '$age voltas ao sol';

    return switch (tone) {
      MessageTone.warm => [
        'Parabéns, $name!$ageWarm Que este novo ano te traga saúde, gargalhadas e tudo aquilo que te faz feliz. Um abraço enorme!',
        if (isFamily)
          'Feliz aniversário, $name! Ter-te na família é um presente todos os dias. Hoje celebramos-te a ti. ❤️'
        else
          'Feliz aniversário, $name! Obrigado por seres uma pessoa tão especial. Que hoje seja um dia à tua medida. ❤️',
        'Muitos parabéns, $name! Desejo-te um ano cheio de momentos bons e de pessoas que te façam sorrir — como tu fazes a quem está à tua volta.',
        'Hoje o dia é teu, $name. Que nunca te falte motivo para sorrir. Parabéns e um beijinho grande!',
      ],
      MessageTone.fun => [
        'Parabéns, $name! 🎉 $ageFun e continuas em excelente forma. O segredo é o bolo, não é?',
        'Feliz aniversário, $name! Hoje as calorias não contam e as velas são só um detalhe. 🎂',
        'Mais um ano mais sábio(a), $name… ou pelo menos com mais histórias para contar. Parabéns! 🥳',
        'Alerta: $name está oficialmente a ficar mais fixe. Parabéns e que a festa esteja à altura! 🎈',
      ],
      MessageTone.formal => [
        'Caro(a) $name, os meus sinceros parabéns. Desejo-lhe um excelente aniversário e um ano repleto de sucessos.',
        'Muitos parabéns, $name. Que este novo ano de vida seja rico em saúde, conquistas pessoais e profissionais.',
        'Feliz aniversário, $name. Votos de um dia muito agradável na companhia de quem mais estima.',
      ],
      MessageTone.short => [
        'Parabéns, $name! 🎂',
        'Feliz aniversário, $name! Um grande abraço.',
        'Muitos parabéns, $name! Aproveita o teu dia. 🎉',
      ],
    };
  }
}
