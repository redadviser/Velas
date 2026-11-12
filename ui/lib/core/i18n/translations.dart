import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Textos traduzidos, lidos de `assets/translations/<língua>.json`. Há dois
/// tipos de chave: as de `core/constants.dart` (`Keys.x`) e, no resto da app,
/// o próprio texto em português (`context.tr('Guardar')`). Uma chave que falte
/// numa língua usa o português (no pt-BR, primeiro o de Portugal).
///
/// Nos widgets usa `context.tr(...)`: assim reconstroem quando a língua muda.
/// Fora deles (modelos, repositórios) usa `tr(...)`, que lê a língua atual.
class Translations {
  Translations._(this.locale, this._strings, this._fallback);

  final Locale locale;
  final Map<String, String> _strings;
  final Map<String, String> _fallback;

  static const fallbackLocale = Locale('pt', 'PT');
  static const supportedLocales = [
    Locale('pt', 'PT'),
    Locale('pt', 'BR'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('de'),
    Locale('it'),
    Locale('nl'),
    Locale('pl'),
    Locale('ro'),
    Locale('uk'),
    Locale('ru'),
    Locale('tr'),
    Locale('ar'),
    Locale('zh'),
    Locale('ja'),
  ];

  /// Etiqueta de cada língua: o nome do ficheiro JSON e o que se guarda nas
  /// preferências ("pt", "pt_BR", "en", ...).
  static final languageCodes = [for (final l in supportedLocales) tagOf(l)];

  /// O nome de cada língua na própria língua (igual em todas as traduções).
  static const languageNames = {
    'pt': 'Português (Portugal)',
    'pt_BR': 'Português (Brasil)',
    'en': 'English',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'it': 'Italiano',
    'nl': 'Nederlands',
    'pl': 'Polski',
    'ro': 'Română',
    'uk': 'Українська',
    'ru': 'Русский',
    'tr': 'Türkçe',
    'ar': 'العربية',
    'zh': '中文（简体）',
    'ja': '日本語',
  };

  /// O país da bandeira de cada língua (desenhada pelo country_flags, não emoji).
  static const languageFlags = {
    'pt': 'PT',
    'pt_BR': 'BR',
    'en': 'GB',
    'es': 'ES',
    'fr': 'FR',
    'de': 'DE',
    'it': 'IT',
    'nl': 'NL',
    'pl': 'PL',
    'ro': 'RO',
    'uk': 'UA',
    'ru': 'RU',
    'tr': 'TR',
    'ar': 'SA',
    'zh': 'CN',
    'ja': 'JP',
  };

  static String tagOf(Locale l) => l.languageCode == 'pt' && l.countryCode == 'BR' ? 'pt_BR' : l.languageCode;

  /// A língua suportada com esta etiqueta (`null` se não houver).
  static Locale? localeOf(String tag) => supportedLocales.where((l) => tagOf(l) == tag).firstOrNull;

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
    final resolved = localeOf(tagOf(locale)) ?? fallbackLocale;
    final tag = tagOf(resolved);
    final pt = await _read('pt');
    if (tag == 'pt') return current = Translations._(resolved, pt, pt);
    final strings = await _read(tag);
    return current = Translations._(resolved, strings, pt);
  }

  /// Escolhe, entre as línguas suportadas, a do telemóvel (português se nenhuma servir).
  static Locale resolve(List<Locale>? preferred) {
    for (final l in preferred ?? const <Locale>[]) {
      if (l.languageCode == 'pt') return l.countryCode == 'BR' ? const Locale('pt', 'BR') : fallbackLocale;
      final match = localeOf(l.languageCode);
      if (match != null) return match;
    }
    return fallbackLocale;
  }

  /// Locale para formatar datas e horas (intl).
  String get dateLocale => switch (tagOf(locale)) {
    'pt' => 'pt_PT',
    final tag => tag,
  };

  /// Texto da [key] com os `{marcadores}` substituídos por [args].
  String get(String key, [Map<String, Object?> args = const {}]) {
    var text = _strings[key] ?? _fallback[key] ?? key;
    for (final e in args.entries) {
      text = text.replaceAll('{${e.key}}', '${e.value}');
    }
    return text;
  }

  /// Plural: usa `<key>.one`, `<key>.other` e, nas línguas que os têm (polaco,
  /// russo, ucraniano, árabe), `.few`, `.many`, `.two` e `.zero`, com
  /// `{count}` = [count]. A forma que falte cai em `.other`.
  String plural(String key, int count, [Map<String, Object?> args = const {}]) {
    bool has(String form) => _strings.containsKey('$key.$form') || _fallback.containsKey('$key.$form');
    // Sem `zero:` (o intl usá-lo-ia para todo o 0, e em francês 0 é singular).
    final form = count == 0 && has('zero')
        ? 'zero'
        : Intl.pluralLogic(count, locale: dateLocale, one: 'one', two: 'two', few: 'few', many: 'many', other: 'other');
    final k = has(form) ? '$key.$form' : '$key.other';
    return get(k, {'count': count, ...args});
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
