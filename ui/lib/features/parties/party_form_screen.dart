import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../data/models/party_models.dart';
import '../auth/auth_widgets.dart';

/// Criar ou editar uma festa ([partyId] = editar; [personId] = já escolhida).
class PartyFormScreen extends ConsumerStatefulWidget {
  const PartyFormScreen({super.key, this.partyId, this.personId});

  final String? partyId;
  final String? personId;

  @override
  ConsumerState<PartyFormScreen> createState() => _PartyFormScreenState();
}

class _PartyFormScreenState extends ConsumerState<PartyFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Party? _existing = widget.partyId == null
      ? null
      : ref.read(partiesProvider).value?.where((p) => p.id == widget.partyId).firstOrNull;
  late final _title = TextEditingController(text: _existing?.title);
  late final _celebrant = TextEditingController(text: _existing?.celebrantName ?? _person?.firstName);
  late final _place = TextEditingController(text: _existing?.place);
  late final _notes = TextEditingController(text: _existing?.notes);
  late String? _personId = _existing?.personId ?? widget.personId;
  late DateTime? _startsAt = _existing?.startsAt;
  bool _saving = false;

  Person? get _person => widget.personId == null ? null : ref.read(dataProvider).person(widget.personId!);

  @override
  void dispose() {
    _title.dispose();
    _celebrant.dispose();
    _place.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final suggested = _personId == null ? null : ref.read(dataProvider).person(_personId!)?.nextBirthday();
    final day = await showDatePicker(
      context: context,
      initialDate: _startsAt ?? suggested ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: 'Dia da festa',
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _startsAt == null ? const TimeOfDay(hour: 19, minute: 30) : TimeOfDay.fromDateTime(_startsAt!),
      helpText: 'A que horas?',
    );
    if (!mounted) return;
    final t = time ?? const TimeOfDay(hour: 19, minute: 30);
    setState(() => _startsAt = DateTime(day.year, day.month, day.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final me = ref.read(currentUserProvider)!.id;
    final base = _existing ?? Party(id: const Uuid().v4(), createdBy: me, title: '', celebrantName: '');
    final party = base.copyWith(
      title: _title.text.trim(),
      celebrantName: _celebrant.text.trim(),
      personId: () => _personId,
      startsAt: () => _startsAt,
      place: _place.text.trim(),
      notes: _notes.text.trim(),
    );
    final router = GoRouter.of(context);
    final ok = await runGuarded(context, () => ref.read(partiesProvider.notifier).run((repo) => repo.saveParty(party)));
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    _existing == null ? router.pushReplacement('/parties/${party.id}') : router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final people = [...ref.watch(dataProvider).people]..sort((a, b) => a.name.compareTo(b.name));
    final d = _startsAt;
    return Scaffold(
      appBar: AppBar(title: Text(_existing == null ? 'Nova festa surpresa' : 'Editar festa')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: context.palette.violetSoft, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Icon(LucideIcons.lock, size: 18, color: context.colors.secondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Só tu e quem convidares veem esta festa. Não convides o aniversariante.',
                      style: context.text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Para quem é?', style: context.text.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: _personId,
              isExpanded: true,
              decoration: const InputDecoration(hintText: 'Escolher da tua lista (opcional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Outra pessoa')),
                for (final p in people)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() {
                _personId = v;
                final p = v == null ? null : ref.read(dataProvider).person(v);
                if (p != null) {
                  _celebrant.text = p.firstName;
                  if (_title.text.trim().isEmpty) _title.text = 'Surpresa para ${p.firstName}';
                }
              }),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _celebrant,
              textCapitalization: TextCapitalization.words,
              validator: (v) => Validators.required(v, 'Diz para quem é a festa.'),
              decoration: const InputDecoration(hintText: 'Nome do aniversariante'),
            ),
            const SizedBox(height: 18),
            Text('A festa', style: context.text.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => Validators.required(v, 'Dá um nome à festa.'),
              decoration: const InputDecoration(hintText: 'Ex.: Jantar surpresa dos 30'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickDate,
              style: OutlinedButton.styleFrom(alignment: AlignmentDirectional.centerStart),
              icon: const Icon(LucideIcons.calendarClock, size: 18),
              label: Text(
                d == null
                    ? 'Escolher dia e hora'
                    : '${Fmt.weekdayDayMonth(d)} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _place,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Onde? (opcional)',
                prefixIcon: Icon(LucideIcons.mapPin, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Notas para os convidados (o que levar, código de vestuário…)',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_existing == null ? 'Criar festa' : 'Guardar')),
            const SizedBox(height: 8),
            Text(
              'Depois de criar, partilha o código para os amigos entrarem.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
