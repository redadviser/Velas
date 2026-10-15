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

    test('existem as quatro línguas: pt, en, es, fr', () {
      expect(langs, ['pt', 'en', 'es', 'fr']);
      expect(keys, isNotEmpty);
    });

    for (final lang in langs) {
      test('$lang.json tem todas as chaves (e só essas)', () {
        final json = jsonFor(lang);
        final expected = {
          for (final k in keys) ...(k.plural ? ['${k.key}.one', '${k.key}.other'] : [k.key]),
        };
        expect(json.keys.toSet().difference(expected), isEmpty, reason: 'chaves a mais em $lang.json');
        expect(expected.difference(json.keys.toSet()), isEmpty, reason: 'chaves em falta em $lang.json');
        expect(json.values.where((v) => v.trim().isEmpty), isEmpty, reason: 'textos vazios em $lang.json');
      });
    }

    test('os {marcadores} são os mesmos em todas as línguas', () {
      final pt = jsonFor('pt');
      for (final lang in langs.skip(1)) {
        final other = jsonFor(lang);
        for (final e in pt.entries) {
          expect(placeholders(other[e.key]!), placeholders(e.value), reason: '${e.key} em $lang');
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

      // Língua não suportada: português.
      final other = await Translations.load(const Locale('de'));
      expect(other.locale, Translations.fallbackLocale);
      expect(other.get(Keys.chatSeen), 'Vista');
    });

    test('escolhe a língua do telemóvel entre as suportadas', () {
      expect(Translations.resolve([const Locale('es', 'MX')]), const Locale('es'));
      expect(Translations.resolve([const Locale('de'), const Locale('fr', 'CA')]), const Locale('fr'));
      expect(Translations.resolve([const Locale('ja')]), Translations.fallbackLocale);
      expect(Translations.resolve(null), Translations.fallbackLocale);
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
      expect(ChatFormat.presence(online: true), 'Online');
      final now = DateTime.now();
      expect(
        ChatFormat.presence(online: false, lastSeenAt: DateTime(now.year, now.month, now.day, 9, 5)),
        'Visto por último hoje às 09:05',
      );
      expect(ChatFormat.presence(online: false), isNull);

      await Translations.load(const Locale('en'));
      expect(ChatFormat.typing(['Gil', 'Ana']), 'Gil and Ana are typing…');
      expect(ChatFormat.seenBy([gil, ana, rui]), 'Seen by Gil and 2 others');
      expect(ChatMessage.previewOf(MessageKind.image, ''), '📷 Photo');
      await Translations.load(const Locale('pt'));
    });
  });
}
