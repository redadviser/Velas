import '../core/i18n/translations.dart';
import '../data/models/models.dart';

enum MessageTone {
  warm('Carinhosa'),
  fun('Divertida'),
  formal('Formal'),
  short('Curta');

  const MessageTone(this.label);

  /// Valor guardado com a mensagem; para mostrar usa [title].
  final String label;

  String get title => switch (this) {
    warm => tr('Carinhosa'),
    fun => tr('Divertida'),
    formal => tr('Formal'),
    short => tr('Curta'),
  };
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
    return switch (tone) {
      MessageTone.warm => [
        if (age == null)
          tr(
            'Parabéns, {name}! Que este novo ano te traga saúde, gargalhadas e tudo aquilo que te faz feliz. Um abraço enorme!',
            {'name': name},
          )
        else
          tr(
            'Parabéns, {name}! {age} anos! Que este novo ano te traga saúde, gargalhadas e tudo aquilo que te faz feliz. Um abraço enorme!',
            {'name': name, 'age': age},
          ),
        if (isFamily)
          tr('Feliz aniversário, {name}! Ter-te na família é um presente todos os dias. Hoje celebramos-te a ti. ❤️', {
            'name': name,
          })
        else
          tr(
            'Feliz aniversário, {name}! Obrigado por seres uma pessoa tão especial. Que hoje seja um dia à tua medida. ❤️',
            {'name': name},
          ),
        tr(
          'Muitos parabéns, {name}! Desejo-te um ano cheio de momentos bons e de pessoas que te façam sorrir, como tu fazes a quem está à tua volta.',
          {'name': name},
        ),
        tr('Hoje o dia é teu, {name}. Que nunca te falte motivo para sorrir. Parabéns e um beijinho grande!', {
          'name': name,
        }),
      ],
      MessageTone.fun => [
        if (age == null)
          tr('Parabéns, {name}! 🎉 mais uma volta ao sol e continuas em excelente forma. O segredo é o bolo, não é?', {
            'name': name,
          })
        else
          tr('Parabéns, {name}! 🎉 {age} voltas ao sol e continuas em excelente forma. O segredo é o bolo, não é?', {
            'name': name,
            'age': age,
          }),
        tr('Feliz aniversário, {name}! Hoje as calorias não contam e as velas são só um detalhe. 🎂', {'name': name}),
        tr('Mais um ano mais sábio(a), {name}… ou pelo menos com mais histórias para contar. Parabéns! 🥳', {
          'name': name,
        }),
        tr('Alerta: {name} está oficialmente a ficar mais fixe. Parabéns e que a festa esteja à altura! 🎈', {
          'name': name,
        }),
      ],
      MessageTone.formal => [
        tr(
          'Caro(a) {name}, os meus sinceros parabéns. Desejo-lhe um excelente aniversário e um ano repleto de sucessos.',
          {'name': name},
        ),
        tr(
          'Muitos parabéns, {name}. Que este novo ano de vida seja rico em saúde, conquistas pessoais e profissionais.',
          {'name': name},
        ),
        tr('Feliz aniversário, {name}. Votos de um dia muito agradável na companhia de quem mais estima.', {
          'name': name,
        }),
      ],
      MessageTone.short => [
        tr('Parabéns, {name}! 🎂', {'name': name}),
        tr('Feliz aniversário, {name}! Um grande abraço.', {'name': name}),
        tr('Muitos parabéns, {name}! Aproveita o teu dia. 🎉', {'name': name}),
      ],
    };
  }
}
