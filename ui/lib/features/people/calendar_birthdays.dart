import 'package:device_calendar_plus/device_calendar_plus.dart';

import 'import_contacts_screen.dart';

/// Um evento do calendário, só com o que interessa para encontrar aniversários.
typedef CalendarItem = ({String id, String title, DateTime start, String calendarName});

/// Calendários que só têm aniversários: o "Aniversários" do Google e do iPhone
/// (gerado a partir dos contactos), noutras línguas também.
final _birthdayCalendar = RegExp(
  r'^(birthdays?|anivers[aá]rios?|cumplea[nñ]os|anniversaires?|geburtstage?|contact birthdays.*|contacts?|contactos)$',
  caseSensitive: false,
);

bool isBirthdayCalendar(String name) => _birthdayCalendar.hasMatch(name.trim());

/// Palavras de "aniversário" no início ou no fim do título.
const _word = r'(?:anivers[aá]rio|aniv\.|parab[eé]ns|cumplea[nñ]os|anniversaire|birthday|bday|b-day|geburtstag)';

/// Entre a palavra e o nome: espaço, dois pontos ou travessão.
const _sep = r'(?:\s*[:\-–]\s*|\s+)';

final _prefix = RegExp('^$_word$_sep(?:d[aoe]s?\\s+|de la\\s+|del\\s+|von\\s+)?(.+)\$', caseSensitive: false);
final _possessive = RegExp(r"^(.+?)(?:'s|’s|s'|’)\s+birthday$", caseSensitive: false);
final _suffix = RegExp('^(.+?)$_sep(?:$_word|faz anos)\$', caseSensitive: false);

/// Emojis de festa e idades como "(30)" ou "- 30 anos" à volta do nome.
final _decorations = RegExp(r'[🎂🎉🎈🥳🎁🍰]|\(\d{1,3}\)|\s[-–]\s*\d{1,3}\s*(anos|years?)?\s*$', unicode: true);

/// O nome num título de aniversário ("Aniversário da Ana", "Ana's birthday",
/// "🎂 Ana - aniversário"), ou `null` se o título não for de um aniversário.
String? birthdayNameFromTitle(String title) {
  final t = title.replaceAll(_decorations, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  for (final re in [_possessive, _prefix, _suffix]) {
    final name = re.firstMatch(t)?.group(1)?.trim();
    if (name != null && name.isNotEmpty && !RegExp('^$_word\$', caseSensitive: false).hasMatch(name)) {
      return name;
    }
  }
  return null;
}

/// Os aniversários encontrados nos eventos: todos os dos calendários de
/// aniversários e, nos outros, os que têm título de aniversário. O ano não se
/// sabe (cada evento é a ocorrência deste ano); fica por preencher.
List<ContactEntry> calendarBirthdays(Iterable<CalendarItem> events) => [
  for (final e in events)
    if ((isBirthdayCalendar(e.calendarName)
            ? birthdayNameFromTitle(e.title) ?? e.title.trim()
            : birthdayNameFromTitle(e.title))
        case final name? when name.isNotEmpty)
      (key: 'cal:${e.id}', name: name, photo: null, date: (day: e.start.day, month: e.start.month, year: null)),
];

/// Lê os eventos do próximo ano (cada aniversário aparece uma vez). Devolve
/// `null` sem acesso ao calendário.
Future<List<CalendarItem>?> readCalendarEvents() async {
  final plugin = DeviceCalendar.instance;
  final status = await plugin.requestPermissions();
  if (status != CalendarPermissionStatus.granted) return null;
  final calendars = {for (final c in await plugin.listCalendars()) c.id: c.name};
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day);
  final events = await plugin.listEvents(from, from.add(const Duration(days: 366)));
  return [
    for (final e in events)
      (id: e.eventId, title: e.title, start: e.startDate, calendarName: calendars[e.calendarId] ?? ''),
  ];
}

/// Abre as definições da app (para dar acesso ao calendário).
Future<void> openCalendarSettings() => DeviceCalendar.instance.openAppSettings();
