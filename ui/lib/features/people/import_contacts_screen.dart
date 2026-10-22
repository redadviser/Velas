import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/utils/text.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../services/notification_service.dart';
import '../auth/auth_widgets.dart';
import 'birthday_picker.dart';
import 'birthday_request.dart';
import 'calendar_birthdays.dart';

/// Um contacto do telemóvel, com o aniversário quando o tem guardado.
typedef ContactEntry = ({String key, String name, Uint8List? photo, BirthDate? date});

ContactEntry? entryOf(Contact c) {
  final name = (c.displayName ?? '').trim();
  if (name.isEmpty) return null;
  return (key: c.id ?? name, name: name, photo: c.photo?.thumbnail, date: birthdayOf(c));
}

/// Os contactos que ainda não estão na lista (pelo nome), sem repetidos
/// (fica o que tem data), por ordem alfabética.
List<ContactEntry> newContacts(Iterable<ContactEntry> found, List<Person> existing) {
  String norm(String s) => s.trim().toLowerCase();
  final known = {for (final p in existing) norm(p.name)};
  final byName = <String, ContactEntry>{};
  for (final c in found) {
    final k = norm(c.name);
    if (k.isEmpty || known.contains(k)) continue;
    final prev = byName[k];
    if (prev == null || (prev.date == null && c.date != null)) byName[k] = c;
  }
  return byName.values.toList()..sort((a, b) => norm(a.name).compareTo(norm(b.name)));
}

/// Etiqueta personalizada que quer dizer "aniversário" (algumas apps de
/// contactos, como a da Xiaomi, gravam-no assim em vez do tipo próprio).
final _birthdayWords = RegExp(r'anivers|birthday|nasc|cumple|geburt|naissance', caseSensitive: false);

/// O aniversário de um contacto, se tiver. Os anos fora do intervalo aceite
/// (ex.: 1604, que o iPhone usa para "sem ano") ficam sem ano.
BirthDate? birthdayOf(Contact c) {
  final e = c.events
      .where((e) => e.label.label == EventLabel.birthday || _birthdayWords.hasMatch(e.label.customLabel ?? ''))
      .firstOrNull;
  final date = e != null ? (year: e.year, month: e.month, day: e.day) : _rawAndroidBirthday(c);
  if (date == null || date.month < 1 || date.month > 12 || date.day < 1 || date.day > 31) return null;
  final year = date.year != null && date.year! >= 1900 && date.year! <= DateTime.now().year ? date.year : null;
  return (day: date.day, month: date.month, year: year);
}

/// Uma data lida de um contacto (o ano pode faltar).
typedef ContactDate = ({int? year, int month, int day});

/// Android: o plugin só aceita datas ISO (`1990-05-03`, `--05-03`). Aqui lê-se
/// a linha original do contacto (`contact_event`: data1 = data, data2 = tipo,
/// data3 = etiqueta) e aceitam-se também datas como `03/05/1990`.
ContactDate? _rawAndroidBirthday(Contact c) {
  final rows = c.android?.debugData?['vnd.android.cursor.item/contact_event'];
  if (rows is! List) return null;
  for (final row in rows) {
    if (row is! Map) continue;
    final type = row['data2'];
    final label = row['data3'] is String ? row['data3'] as String : '';
    // 3 = ContactsContract.CommonDataKinds.Event.TYPE_BIRTHDAY
    if (type != 3 && !_birthdayWords.hasMatch(label)) continue;
    final date = row['data1'] is String ? parseContactDate(row['data1'] as String) : null;
    if (date != null) return date;
  }
  return null;
}

/// Datas como as apps de contactos as gravam: `1990-05-03`, `19900503`,
/// `--05-03`, `--0503`, e com o dia primeiro (como em Portugal) `03/05/1990`,
/// `03-05-1990`, `03.05.1990` ou `03/05`.
ContactDate? parseContactDate(String raw) {
  final s = raw.trim().split(RegExp(r'[T ]')).first;
  int? n(String? v) => v == null ? null : int.tryParse(v);
  var m = RegExp(r'^(\d{4})-?(\d{2})-?(\d{2})$').firstMatch(s);
  if (m != null) return (year: n(m.group(1)), month: n(m.group(2))!, day: n(m.group(3))!);
  m = RegExp(r'^--(\d{2})-?(\d{2})$').firstMatch(s);
  if (m != null) return (year: null, month: n(m.group(1))!, day: n(m.group(2))!);
  m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{4}))?$').firstMatch(s);
  if (m != null) return (year: n(m.group(3)), month: n(m.group(2))!, day: n(m.group(1))!);
  return null;
}

/// Adicionar aniversários a partir dos contactos do telemóvel. Quase ninguém
/// tem a data guardada no contacto, por isso mostram-se todos: os que têm
/// data vêm marcados; nos outros basta tocar e escolher o dia (nome e foto
/// já vêm do contacto).
///
/// Com [fromCalendar], os aniversários vêm do calendário do telemóvel (o do
/// Google ou do iPhone): eventos de aniversário, todos já com dia e mês.
class ImportContactsScreen extends ConsumerStatefulWidget {
  const ImportContactsScreen({super.key, this.welcome = false, this.fromCalendar = false});

  /// Aberto sozinho na primeira entrada na conta: com boas-vindas e "Depois".
  final bool welcome;
  final bool fromCalendar;

  @override
  ConsumerState<ImportContactsScreen> createState() => _ImportContactsScreenState();
}

enum _Stage { loading, denied, ready }

class _ImportContactsScreenState extends ConsumerState<ImportContactsScreen> {
  _Stage _stage = _Stage.loading;
  List<ContactEntry> _entries = const [];
  int _contactsRead = 0;

  /// Datas escolhidas aqui, por contacto.
  final _picked = <String, BirthDate>{};
  final _selected = <String>{};
  final _search = TextEditingController();
  String _query = '';
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  BirthDate? _dateOf(ContactEntry c) => _picked[c.key] ?? c.date;

  Future<void> _load() async {
    setState(() => _stage = _Stage.loading);
    if (widget.fromCalendar) return _loadCalendar();
    try {
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
        if (mounted) setState(() => _stage = _Stage.denied);
        return;
      }
      final contacts = await FlutterContacts.getAll(
        properties: {
          ContactProperty.name,
          ContactProperty.event,
          ContactProperty.photoThumbnail,
          // As linhas originais, para as datas que o plugin não entende (ver _rawAndroidBirthday).
          if (Platform.isAndroid) ContactProperty.debugData,
        },
      );
      final entries = newContacts([for (final c in contacts) ?entryOf(c)], ref.read(dataProvider).people);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _contactsRead = contacts.length;
        _selected
          ..clear()
          ..addAll(entries.where((c) => c.date != null).map((c) => c.key));
        _stage = _Stage.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.denied);
    }
  }

  Future<void> _loadCalendar() async {
    try {
      final events = await readCalendarEvents();
      if (events == null) {
        if (mounted) setState(() => _stage = _Stage.denied);
        return;
      }
      final found = calendarBirthdays(events);
      final entries = newContacts(found, ref.read(dataProvider).people);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _contactsRead = found.length;
        _selected
          ..clear()
          ..addAll(entries.map((c) => c.key));
        _stage = _Stage.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.denied);
    }
  }

  Future<void> _pick(ContactEntry c) async {
    final date = await showBirthdayPicker(context, initial: _dateOf(c));
    if (date == null || !mounted) return;
    setState(() {
      _picked[c.key] = date;
      _selected.add(c.key);
    });
  }

  Future<void> _import() async {
    final repo = ref.read(dataRepositoryProvider);
    if (repo == null) return;
    final isFirst = ref.read(dataProvider).people.isEmpty;
    final now = DateTime.now();
    final people = <Person>[];
    final photos = <String, Uint8List>{};
    for (final c in _entries.where((c) => _selected.contains(c.key))) {
      final d = _dateOf(c);
      if (d == null) continue;
      final p = Person(id: const Uuid().v4(), name: c.name, day: d.day, month: d.month, year: d.year, createdAt: now);
      people.add(p);
      if (c.photo != null) photos[p.id] = c.photo!;
    }
    setState(() => _importing = true);
    final ok = await runGuarded(
      context,
      () => repo.importPeople(people, photos: photos),
      success: people.length == 1 ? '1 aniversário adicionado.' : '${people.length} aniversários adicionados.',
    );
    if (!mounted) return;
    setState(() => _importing = false);
    if (!ok) return;
    if (isFirst) NotificationService.instance.requestPermission();
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(currentUserProvider)?.firstName ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fromCalendar ? 'Importar do calendário' : 'Adicionar dos contactos'),
        actions: [
          if (widget.welcome) TextButton(onPressed: () => context.pop(), child: const Text('Depois')),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.welcome)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '${name.isEmpty ? 'Olá' : 'Olá, $name'}! Começa pelos aniversários de quem importa: '
                'escolhe dos teus contactos ou pede a data por link. Nós lembramos-te a tempo.',
                style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground),
              ),
            ),
          if (!widget.fromCalendar)
            const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 4), child: BirthdayRequestCard()),
          Expanded(
            child: _stage == _Stage.loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                : _content(context),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    return switch (_stage) {
      _Stage.loading => const SizedBox.shrink(),
      _Stage.denied => EmptyState(
        icon: widget.fromCalendar ? LucideIcons.calendarDays : LucideIcons.contactRound,
        title: widget.fromCalendar ? 'Sem acesso ao calendário' : 'Sem acesso aos contactos',
        message: widget.fromCalendar
            ? 'Para importar os aniversários do calendário, permite o acesso nas definições do telemóvel.'
            : 'Para adicionar a partir dos contactos, permite o acesso nas definições do telemóvel.',
        action: FilledButton(
          onPressed: () async {
            await (widget.fromCalendar ? openCalendarSettings() : FlutterContacts.permissions.openSettings());
            if (mounted) _load();
          },
          style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
          child: const Text('Abrir definições'),
        ),
      ),
      _Stage.ready when _entries.isEmpty && widget.fromCalendar => EmptyState(
        icon: LucideIcons.calendarDays,
        title: _contactsRead == 0 ? 'Sem aniversários no calendário' : 'Já tens todos',
        message: _contactsRead == 0
            ? 'Não encontrámos aniversários no teu calendário, como "Aniversário da Ana" ou o calendário Aniversários do Google.'
            : 'Todos os aniversários do teu calendário já estão na tua lista.',
      ),
      _Stage.ready when _entries.isEmpty => EmptyState(
        icon: LucideIcons.cake,
        title: _contactsRead == 0 ? 'Sem contactos' : 'Já tens todos',
        message: _contactsRead == 0
            ? 'Não conseguimos ler nenhum contacto. Confirma nas definições que a Birthdayly tem acesso a todos.'
            : 'Todos os teus contactos já estão na tua lista.',
      ),
      _Stage.ready => _list(context),
    };
  }

  Widget _list(BuildContext context) {
    final muted = context.palette.mutedForeground;
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty ? _entries : _entries.where((c) => c.name.toLowerCase().contains(q)).toList();
    // Secções pela data do contacto (escolher uma data não muda a linha de sítio).
    final dated = shown.where((c) => c.date != null).toList();
    final undated = shown.where((c) => c.date == null).toList();
    final rows = <Object>[
      if (dated.isNotEmpty) '${widget.fromCalendar ? 'Do calendário' : 'Com data no contacto'} · ${dated.length}',
      ...dated,
      if (undated.isNotEmpty) 'Sem data · toca para escolher',
      ...undated,
    ];
    final count = _selected.where((k) => _entries.any((c) => c.key == k && _dateOf(c) != null)).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: widget.fromCalendar ? 'Procurar' : 'Procurar contacto',
              prefixIcon: Icon(LucideIcons.search, size: 18),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              if (row is String) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    row,
                    style: context.text.labelMedium?.copyWith(color: muted, fontWeight: FontWeight.w600),
                  ),
                );
              }
              final c = row as ContactEntry;
              final d = _dateOf(c);
              return ListTile(
                onTap: () => _pick(c),
                leading: CircleAvatar(
                  backgroundColor: context.palette.accent,
                  backgroundImage: c.photo == null ? null : MemoryImage(c.photo!),
                  child: c.photo == null
                      ? Text(initialOf(c.name), style: TextStyle(color: context.palette.accentForeground))
                      : null,
                ),
                title: Text(c.name),
                subtitle: d == null
                    ? Text('Escolher data', style: TextStyle(color: context.colors.primary))
                    : Text(Fmt.birthDate(d.day, d.month, d.year), style: TextStyle(color: muted)),
                trailing: d == null
                    ? Icon(LucideIcons.calendarPlus, size: 20, color: muted)
                    : Checkbox(
                        value: _selected.contains(c.key),
                        onChanged: (v) => setState(() => v == true ? _selected.add(c.key) : _selected.remove(c.key)),
                      ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: LoadingButton(
              label: count == 1 ? 'Adicionar 1 aniversário' : 'Adicionar $count aniversários',
              loading: _importing,
              onPressed: count == 0 ? null : _import,
            ),
          ),
        ),
      ],
    );
  }
}
