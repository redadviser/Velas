import 'dart:convert';
import 'dart:io';

import 'package:aniversarios/core/constants.dart';
import 'package:aniversarios/core/i18n/translations.dart';
import 'package:aniversarios/data/models/chat_models.dart';
import 'package:aniversarios/features/chat/chat_format.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// As chaves de core/constants.dart (com as de plural marcadas).
List<({String key, bool plural})> constantKeys() {
  final lines = File('lib/core/constants.dart').readAsLinesSync();
  final keys = <({String key, bool plural})>[];
  for (var i = 0; i < lines.length; i++) {
    final m = RegExp(r"static const \w+ = '([^']+)';").firstMatch(lines[i]);
    if (m != null) keys.add((key: m.group(1)!, plural: i > 0 && lines[i - 1].contains('Plural')));
  }
  return keys;
}

/// Os textos em português usados como chave no código: os literais dentro de
/// `tr('...')` / `context.tr('...')` e de `AppException('...')`.
Set<String> textKeys() {
  const singleQuoted = r"'(?:[^'\\]|\\.)*'";
  const doubleQuoted = r'"(?:[^"\\]|\\.)*"';
  const literal = '(?:$singleQuoted|$doubleQuoted)';
  final call = RegExp(r'(?:^|[^\w])(?:tr|AppException)\(\s*((?:' + literal + r'\s*)+)[,)]', multiLine: true);
  final part = RegExp(literal);
  String decode(String s) => s
      .substring(1, s.length - 1)
      .replaceAllMapped(
        RegExp(r'\\(.)'),
        (m) => switch (m.group(1)!) {
          'n' => '\n',
          't' => '\t',
          final c => c,
        },
      );
  final keys = <String>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    for (final m in call.allMatches(f.readAsStringSync())) {
      final parts = part.allMatches(m.group(1)!).map((p) => p.group(0)!).toList();
      // Com interpolação não é chave fixa (ex.: 'language.$code').
      if (parts.any((p) => RegExp(r'(?<!\\)\$').hasMatch(p))) continue;
      keys.add(parts.map(decode).join());
    }
  }
  return keys;
}

Map<String, String> jsonFor(String lang) =>
    (jsonDecode(File('assets/translations/$lang.json').readAsStringSync()) as Map).cast<String, String>();

Set<String> placeholders(String s) => RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
  });

  group('Ficheiros de tradução', () {
    final langs = Translations.languageCodes;
    final keys = constantKeys();
    final texts = textKeys();
    final plurals = {for (final k in keys.where((k) => k.plural)) k.key};
    // Formas extra de plural que só algumas línguas usam.
    bool extraPlural(String k) =>
        RegExp(r'\.(zero|two|few|many)$').hasMatch(k) && plurals.contains(k.substring(0, k.lastIndexOf('.')));

    test('existem as 16 línguas', () {
      expect(langs, [
        'pt',
        'pt_BR',
        'en',
        'es',
        'fr',
        'de',
        'it',
        'nl',
        'pl',
        'ro',
        'uk',
        'ru',
        'tr',
        'ar',
        'zh',
        'ja',
      ]);
      expect(keys, isNotEmpty);
      expect(texts, isNotEmpty);
      expect(Translations.languageNames.keys.toSet(), langs.toSet());
      expect(Translations.languageFlags.keys.toSet(), langs.toSet());
    });

    for (final lang in langs) {
      test('$lang.json tem todas as chaves (e só essas)', () {
        final json = jsonFor(lang);
        final expected = {
          for (final k in keys) ...(k.plural ? ['${k.key}.one', '${k.key}.other'] : [k.key]),
          // No português, o próprio texto é a tradução.
          if (lang != 'pt') ...texts,
        };
        final extra = json.keys.toSet().difference(expected).where((k) => !extraPlural(k));
        expect(extra, isEmpty, reason: 'chaves a mais em $lang.json');
        expect(expected.difference(json.keys.toSet()), isEmpty, reason: 'chaves em falta em $lang.json');
        expect(json.values.where((v) => v.trim().isEmpty), isEmpty, reason: 'textos vazios em $lang.json');
      });
    }

    test('os {marcadores} são os mesmos em todas as línguas', () {
      final pt = {...jsonFor('pt'), for (final t in texts) t: t};
      for (final lang in langs.skip(1)) {
        final other = jsonFor(lang);
        for (final e in other.entries) {
          final base = pt[e.key] ?? pt['${e.key.substring(0, e.key.lastIndexOf('.'))}.other'];
          // Nas formas de plural pode aparecer {count} mesmo que o português escreva "1"
          // (em ucraniano ou russo, a forma "one" também serve para 21, 31...).
          final plural = RegExp(r'\.(zero|one|two|few|many|other)$').hasMatch(e.key);
          expect(
            placeholders(e.value).difference(plural ? {'count'} : const <String>{}),
            placeholders(base!).difference(plural ? {'count'} : const <String>{}),
            reason: '${e.key} em $lang',
          );
        }
      }
    });
  });

  group('Translations', () {
    test('substitui marcadores, faz plurais e devolve a chave se não existir', () async {
      final en = await Translations.load(const Locale('en'));
      expect(en.get(Keys.chatTypingOne, {'name': 'Gil'}), 'Gil is typing…');
      expect(en.plural(Keys.commonPeople, 1), '1 person');
      expect(en.plural(Keys.commonPeople, 3), '3 people');
      expect(en.get('nao.existe'), 'nao.existe');
      expect(tr(Keys.chatSeen), 'Seen'); // a língua carregada passa a ser a atual

      final fr = await Translations.load(const Locale('fr'));
      expect(fr.plural(Keys.commonPeople, 0), '0 personne'); // em francês, 0 é singular

      // Plurais com mais formas: em russo, 21 usa a forma "one" com o número.
      final ru = await Translations.load(const Locale('ru'));
      expect(ru.plural(Keys.homeInboxUnread, 21), contains('21'));
      // 3 e 5 usam formas diferentes (.few e .many).
      expect(
        ru.plural(Keys.homeInboxUnread, 3).replaceAll('3', ''),
        isNot(ru.plural(Keys.homeInboxUnread, 5).replaceAll('5', '')),
      );

      // Língua não suportada: português.
      final other = await Translations.load(const Locale('ko'));
      expect(other.locale, Translations.fallbackLocale);
      expect(other.get(Keys.chatSeen), 'Vista');
    });

    test('escolhe a língua do telemóvel entre as suportadas', () {
      expect(Translations.resolve([const Locale('es', 'MX')]), const Locale('es'));
      expect(Translations.resolve([const Locale('ko'), const Locale('fr', 'CA')]), const Locale('fr'));
      expect(Translations.resolve([const Locale('ja', 'JP')]), const Locale('ja'));
      expect(Translations.resolve([const Locale('pt', 'BR')]), const Locale('pt', 'BR'));
      expect(Translations.resolve([const Locale('pt', 'AO')]), Translations.fallbackLocale);
      expect(Translations.resolve([const Locale('ko')]), Translations.fallbackLocale);
      expect(Translations.resolve(null), Translations.fallbackLocale);
      expect(Translations.tagOf(const Locale('pt', 'BR')), 'pt_BR');
      expect(Translations.localeOf('pt_BR'), const Locale('pt', 'BR'));
    });

    test('frases das conversas em português e em inglês', () async {
      const gil = ChatUser(userId: 'g', name: 'Gil Costa');
      const ana = ChatUser(userId: 'a', name: 'Ana');
      const rui = ChatUser(userId: 'r', name: 'Rui');

      await Translations.load(const Locale('pt'));
      expect(ChatFormat.typing(['Gil Costa']), 'Gil está a escrever…');
      expect(ChatFormat.typing(['Gil', 'Ana']), 'Gil e Ana estão a escrever…');
      expect(ChatFormat.typing(['Gil', 'Ana', 'Rui']), '3 pessoas estão a escrever…');
      expect(ChatFormat.seenBy([gil]), 'Vista por Gil');
      expect(ChatFormat.seenBy([gil, ana]), 'Vista por Gil e Ana');
      expect(ChatFormat.seenBy([gil, ana, rui]), 'Vista por Gil e mais 2');
      expect(ChatFormat.seenBy([gil, ana], others: 2), 'Vista por todos');

      await Translations.load(const Locale('en'));
      expect(ChatFormat.typing(['Gil', 'Ana']), 'Gil and Ana are typing…');
      expect(ChatFormat.seenBy([gil, ana, rui]), 'Seen by Gil and 2 others');
      expect(ChatMessage.previewOf(MessageKind.image, ''), '📷 Photo');
      await Translations.load(const Locale('pt'));
    });
  });
}
