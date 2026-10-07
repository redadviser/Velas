import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../core/utils/errors.dart';
import '../core/utils/text.dart';
import '../data/models/models.dart';
import 'google_service.dart';

enum ContactSource { device, google }

/// Contacto com data de aniversário, pronto a importar.
class ContactCandidate {
  const ContactCandidate({
    required this.key,
    required this.name,
    required this.day,
    required this.month,
    this.year,
    this.photo,
    this.photoUrl,
  });

  /// Identificador na origem (para a seleção na lista).
  final String key;
  final String name;
  final int day;
  final int month;
  final int? year;

  /// Miniatura (contactos do telemóvel).
  final Uint8List? photo;

  /// Fotografia remota (Google), descarregada só ao importar.
  final String? photoUrl;

  static String _key(String name, int day, int month) => '${foldText(name.trim())}|$day|$month';

  String get _dedupeKey => _key(name, day, month);

  /// Chaves das pessoas que já estão na lista (ver [isIn]).
  static Set<String> keysOf(List<Person> people) => {for (final p in people) _key(p.name, p.day, p.month)};

  /// Já existe na lista do utilizador (mesmo nome e dia de aniversário).
  /// [existing] vem de [keysOf].
  bool isIn(Set<String> existing) => existing.contains(_dedupeKey);

  Person toPerson({String? categoryId}) => Person(
    id: const Uuid().v4(),
    name: name.trim(),
    day: day,
    month: month,
    year: year,
    categoryId: categoryId,
    createdAt: DateTime.now(),
  );
}

class ContactScan {
  const ContactScan({required this.candidates, required this.withoutBirthday});

  /// Ordenados por nome, sem repetidos.
  final List<ContactCandidate> candidates;

  /// Contactos ignorados por não terem data de aniversário.
  final int withoutBirthday;
}

/// Lê aniversários dos contactos do telemóvel (iPhone/iCloud, Android e as
/// contas sincronizadas nele) ou do Google Contacts.
class ContactsImporter {
  const ContactsImporter._();

  /// Ano válido ou `null` (o iOS usa 1604 para "sem ano").
  static int? _year(int? y) => y == null || y < 1900 || y > DateTime.now().year ? null : y;

  /// Dia possível nesse mês (29 de fevereiro é válido).
  static bool _validDate(int day, int month) =>
      month >= 1 && month <= 12 && day >= 1 && day <= const [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];

  static ContactScan _finish(List<ContactCandidate> list, int withoutBirthday) {
    final seen = <String>{};
    final unique = [
      for (final c in list)
        if (seen.add(c._dedupeKey)) c,
    ]..sort((a, b) => foldText(a.name).compareTo(foldText(b.name)));
    return ContactScan(candidates: unique, withoutBirthday: withoutBirthday);
  }

  // Telemóvel ---------------------------------------------------------------

  static Future<ContactScan> fromDevice() async {
    final status = await FlutterContacts.permissions.request(PermissionType.read);
    if (status == PermissionStatus.permanentlyDenied || status == PermissionStatus.restricted) {
      throw const ContactsPermissionException();
    }
    if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
      throw const AppException('Sem acesso aos contactos não é possível importar.');
    }
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.name, ContactProperty.event, ContactProperty.photoThumbnail},
    );
    final list = <ContactCandidate>[];
    var without = 0;
    for (final c in contacts) {
      final name = (c.displayName ?? '').trim();
      final birthday = c.events.where((e) => e.label.label == EventLabel.birthday).firstOrNull;
      if (name.isEmpty || birthday == null || !_validDate(birthday.day, birthday.month)) {
        without++;
        continue;
      }
      list.add(
        ContactCandidate(
          key: 'device:${c.id}',
          name: name,
          day: birthday.day,
          month: birthday.month,
          year: _year(birthday.year),
          photo: c.photo?.thumbnail,
        ),
      );
    }
    return _finish(list, without);
  }

  static Future<void> openSettings() => FlutterContacts.permissions.openSettings();

  // Google --------------------------------------------------------------------

  static Future<ContactScan> fromGoogle({http.Client? client}) async {
    final token = await GoogleService.instance.contactsAccessToken();
    final http0 = client ?? http.Client();
    final connections = <Map<String, dynamic>>[];
    String? pageToken;
    try {
      do {
        final uri = Uri.https('people.googleapis.com', '/v1/people/me/connections', {
          'personFields': 'names,birthdays,photos',
          'pageSize': '1000',
          'pageToken': ?pageToken,
        });
        final res = await http0.get(uri, headers: {'Authorization': 'Bearer $token'});
        if (res.statusCode == 401 || res.statusCode == 403) {
          throw const AppException('O Google não autorizou o acesso aos contactos. Tenta novamente.');
        }
        if (res.statusCode != 200) throw const AppException('Não foi possível ler os contactos do Google.');
        final page = GooglePage.parse(res.body);
        connections.addAll(page.connections);
        pageToken = page.nextPageToken;
      } while (pageToken != null && connections.length < 10000);
    } finally {
      if (client == null) http0.close();
    }
    return parseGoogleConnections(connections);
  }

  /// Converte as ligações da People API (público para os testes).
  static ContactScan parseGoogleConnections(List<Map<String, dynamic>> connections) {
    final list = <ContactCandidate>[];
    var without = 0;
    for (final c in connections) {
      final names = (c['names'] as List?) ?? const [];
      final name = names.isEmpty ? '' : ((names.first as Map)['displayName'] as String? ?? '').trim();
      final birthdays = [for (final b in (c['birthdays'] as List?) ?? const []) (b as Map).cast<String, dynamic>()];
      // Preferir a data principal e, se houver várias, a que tem o ano.
      birthdays.sort((a, b) {
        int score(Map<String, dynamic> m) =>
            ((m['metadata'] as Map?)?['primary'] == true ? 2 : 0) + ((m['date'] as Map?)?['year'] != null ? 1 : 0);
        return score(b) - score(a);
      });
      final date = birthdays.map((b) => b['date'] as Map?).whereType<Map>().firstOrNull;
      final day = (date?['day'] as num?)?.toInt();
      final month = (date?['month'] as num?)?.toInt();
      if (name.isEmpty || day == null || month == null || !_validDate(day, month)) {
        without++;
        continue;
      }
      final photo = [
        for (final p in (c['photos'] as List?) ?? const [])
          if ((p as Map)['default'] != true && p['url'] is String) p['url'] as String,
      ].firstOrNull;
      list.add(
        ContactCandidate(
          key: 'google:${c['resourceName'] ?? name}',
          name: name,
          day: day,
          month: month,
          year: _year((date?['year'] as num?)?.toInt()),
          photoUrl: photo,
        ),
      );
    }
    return _finish(list, without);
  }

  /// Fotografia de um contacto Google (falhas ignoradas).
  static Future<Uint8List?> downloadPhoto(String url, {http.Client? client}) async {
    try {
      final res = await (client?.get ?? http.get)(Uri.parse(url)).timeout(const Duration(seconds: 10));
      return res.statusCode == 200 && res.bodyBytes.isNotEmpty ? res.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }
}

/// Uma página da resposta `people.connections.list`.
class GooglePage {
  const GooglePage(this.connections, this.nextPageToken);

  final List<Map<String, dynamic>> connections;
  final String? nextPageToken;

  factory GooglePage.parse(String body) {
    final j = (jsonDecode(body) as Map).cast<String, dynamic>();
    return GooglePage(
      [for (final c in (j['connections'] as List?) ?? const []) (c as Map).cast<String, dynamic>()],
      j['nextPageToken'] as String?,
    );
  }
}

/// O utilizador recusou o acesso de vez: só nas Definições do sistema.
class ContactsPermissionException extends AppException {
  const ContactsPermissionException()
    : super('A Velas não tem acesso aos contactos. Ativa-o nas Definições do telemóvel.');
}
