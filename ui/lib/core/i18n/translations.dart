import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Textos traduzidos, lidos de `assets/translations/<língua>.json` (chaves em
/// `core/constants.dart`). Uma chave que falte numa língua usa o português.
///
/// Nos widgets usa `context.tr(...)`: assim reconstroem quando a língua muda.
/// Fora deles (modelos, repositórios) usa `tr(...)`, que lê a língua atual.
class Translations {
  Translations._(this.locale, this._strings, this._fallback);

  final Locale locale;
  final Map<String, String> _strings;
  final Map<String, String> _fallback;

  static const fallbackLocale = Locale('pt', 'PT');
  static const supportedLocales = [Locale('pt', 'PT'), Locale('en'), Locale('es'), Locale('fr')];
  static const languageCodes = ['pt', 'en', 'es', 'fr'];

  /// A última língua carregada (usada por [tr]).
  static Translations current = Translations._(fallbackLocale, const {}, const {});

  static const LocalizationsDelegate<Translations> delegate = _TranslationsDelegate();

  static Translations of(BuildContext context) => Localizations.of<Translations>(context, Translations) ?? current;

  static Future<Map<String, String>> _read(String code) async {
    final raw = await rootBundle.loadString('assets/translations/$code.json');
    return (jsonDecode(raw) as Map).cast<String, String>();
  }

  /// Carrega a língua (e o português, para as chaves em falta) e torna-a a atual.
  static Future<Translations> load(Locale locale) async {
    final code = languageCodes.contains(locale.languageCode) ? locale.languageCode : 'pt';
    final fallback = code == 'pt' ? null : await _read('pt');
    final strings = await _read(code);
    final resolved = code == 'pt' ? fallbackLocale : Locale(code);
    return current = Translations._(resolved, strings, fallback ?? strings);
  }

  /// Escolhe, entre as línguas suportadas, a do telemóvel (português se nenhuma servir).
  static Locale resolve(List<Locale>? preferred) {
    for (final l in preferred ?? const <Locale>[]) {
      for (final s in supportedLocales) {
        if (s.languageCode == l.languageCode) return s;
      }
    }
    return fallbackLocale;
  }

  /// Locale para formatar datas e horas (intl).
  String get dateLocale => locale.languageCode == 'pt' ? 'pt_PT' : locale.languageCode;

  /// Texto da [key] com os `{marcadores}` substituídos por [args].
  String get(String key, [Map<String, Object?> args = const {}]) {
    var text = _strings[key] ?? _fallback[key] ?? key;
    for (final e in args.entries) {
      text = text.replaceAll('{${e.key}}', '${e.value}');
    }
    return text;
  }

  /// Plural: usa `<key>.one` ou `<key>.other`, com `{count}` = [count].
  String plural(String key, int count, [Map<String, Object?> args = const {}]) {
    // Em francês, 0 também é singular ("0 personne").
    final one = count == 1 || (locale.languageCode == 'fr' && count == 0);
    return get('$key.${one ? 'one' : 'other'}', {'count': count, ...args});
  }

  /// "14:05".
  String time(DateTime d) => DateFormat.Hm(dateLocale).format(d);
}

/// Texto na língua atual, fora dos widgets.
String tr(String key, [Map<String, Object?> args = const {}]) => Translations.current.get(key, args);

/// Plural na língua atual, fora dos widgets.
String trPlural(String key, int count, [Map<String, Object?> args = const {}]) =>
    Translations.current.plural(key, count, args);

extension TranslationsContext on BuildContext {
  /// Texto traduzido; o widget reconstrói quando a língua muda.
  String tr(String key, [Map<String, Object?> args = const {}]) => Translations.of(this).get(key, args);

  String trPlural(String key, int count, [Map<String, Object?> args = const {}]) =>
      Translations.of(this).plural(key, count, args);

  Translations get translations => Translations.of(this);
}

class _TranslationsDelegate extends LocalizationsDelegate<Translations> {
  const _TranslationsDelegate();

  @override
  bool isSupported(Locale locale) => Translations.languageCodes.contains(locale.languageCode);

  @override
  Future<Translations> load(Locale locale) => Translations.load(locale);

  @override
  bool shouldReload(_TranslationsDelegate old) => false;
}
