import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../auth/auth_widgets.dart';
import '../people/birthday_picker.dart';

/// Ícone e tom (índice de [AppColors.tones]) de cada tipo.
(IconData, int) specialDateStyle(SpecialDateKind kind) => switch (kind) {
  SpecialDateKind.couple => (LucideIcons.heart, 0),
  SpecialDateKind.wedding => (LucideIcons.gem, 1),
  SpecialDateKind.family => (LucideIcons.house, 3),
  SpecialDateKind.memorial => (LucideIcons.flower2, 4),
  SpecialDateKind.other => (LucideIcons.star, 2),
};

class SpecialDatesScreen extends ConsumerWidget {
  const SpecialDatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final dates = data.upcomingSpecialDates;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Datas especiais'),
        actions: [
          IconButton(
            tooltip: 'Nova data',
            icon: const Icon(LucideIcons.plus),
            onPressed: () => showSpecialDateEditor(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: context.palette.softGradient,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Column(
              children: [
                IconBadge(icon: LucideIcons.heart, size: 48),
                const SizedBox(height: 10),
                Text(
                  'Mais datas, mais carinho',
                  textAlign: TextAlign.center,
                  style: AppTheme.display(context, size: 20),
                ),
                const SizedBox(height: 4),
                Text(
                  'Casamentos, namoros, o Dia da Mãe ou um dia só vosso. Guarda-os e lembramos-te a tempo.',
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final d in dates) ...[
            SpecialDateTile(
              date: d,
              data: data,
              onTap: () => showSpecialDateEditor(context, ref, date: d),
            ),
            const SizedBox(height: 10),
          ],
          DashedButton(
            icon: LucideIcons.plus,
            label: dates.isEmpty ? 'Criar a primeira data' : 'Criar outra data',
            onTap: () => showSpecialDateEditor(context, ref),
          ),
        ],
      ),
    );
  }
}

class SpecialDateTile extends StatelessWidget {
  const SpecialDateTile({super.key, required this.date, required this.data, this.onTap});

  final SpecialDate date;
  final AppData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = specialDateStyle(date.kind);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg) = isDark
        ? (context.palette.muted, Color.lerp(AppColors.swatches[tone], Colors.white, 0.45)!)
        : AppColors.tones[tone];
    final days = date.daysUntil();
    final person = date.personId == null ? null : data.person(date.personId!);
    final years = date.years;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBadge(icon: icon, background: bg, foreground: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date.title, style: context.text.titleSmall),
                Text(
                  [
                    ?person?.firstName,
                    Fmt.dayMonth(date.nextDate()),
                    if (years != null && years > 0) '$years anos',
                  ].join(' · '),
                  style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DaysPill(days: days),
        ],
      ),
    );
  }
}

Future<void> showSpecialDateEditor(BuildContext context, WidgetRef ref, {SpecialDate? date, String? personId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => _Editor(date: date, personId: personId),
  );
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({this.date, this.personId});

  final SpecialDate? date;
  final String? personId;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.date?.title);
  late final _notes = TextEditingController(text: widget.date?.notes);
  late SpecialDateKind _kind = widget.date?.kind ?? SpecialDateKind.couple;
  late BirthDate? _when = widget.date == null
      ? null
      : (day: widget.date!.day, month: widget.date!.month, year: widget.date!.year);
  late String? _personId = widget.date?.personId ?? widget.personId;
  bool _missingDate = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final valid = _form.currentState!.validate();
    setState(() => _missingDate = _when == null);
    if (!valid || _when == null) return;
    final w = _when!;
    final base =
        widget.date ??
        SpecialDate(id: const Uuid().v4(), title: '', day: w.day, month: w.month, createdAt: DateTime.now());
    final saved = base.copyWith(
      title: _title.text.trim(),
      kind: _kind,
      day: w.day,
      month: w.month,
      year: () => w.year,
      personId: () => _personId,
      notes: _notes.text.trim(),
    );
    final nav = Navigator.of(context);
    if (await runGuarded(context, () => ref.read(dataRepositoryProvider)!.saveSpecialDate(saved))) nav.pop();
  }

  Future<void> _delete() async {
    final nav = Navigator.of(context);
    final ok = await runGuarded(
      context,
      () => ref.read(dataRepositoryProvider)!.deleteSpecialDate(widget.date!.id),
      success: 'Data apagada.',
    );
    if (ok) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final people = [...ref.watch(dataProvider).people]..sort((a, b) => a.name.compareTo(b.name));
    final w = _when;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.date == null ? 'Nova data especial' : 'Editar data',
                  style: AppTheme.display(context, size: 22),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  autofocus: widget.date == null,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => Validators.required(v, 'Dá um nome à data.'),
                  decoration: const InputDecoration(hintText: 'Ex.: Casamento dos avós'),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in SpecialDateKind.values)
                      ChoiceChip(
                        avatar: Icon(
                          specialDateStyle(k).$1,
                          size: 16,
                          color: _kind == k ? context.colors.surface : context.palette.mutedForeground,
                        ),
                        label: Text(k.label),
                        selected: _kind == k,
                        onSelected: (_) => setState(() => _kind = k),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showBirthdayPicker(context, initial: _when);
                    if (picked != null) setState(() => _when = picked);
                  },
                  style: OutlinedButton.styleFrom(
                    alignment: AlignmentDirectional.centerStart,
                    side: BorderSide(color: _missingDate ? context.colors.error : context.palette.border),
                  ),
                  icon: const Icon(LucideIcons.calendarHeart, size: 18),
                  label: Text(w == null ? 'Escolher o dia' : Fmt.birthDate(w.day, w.month, w.year)),
                ),
                if (_missingDate)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 12),
                    child: Text('Escolhe o dia.', style: context.text.bodySmall?.copyWith(color: context.colors.error)),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _personId,
                  isExpanded: true,
                  decoration: const InputDecoration(hintText: 'De quem é? (opcional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Ninguém em especial')),
                    for (final p in people)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text(p.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _personId = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Notas (opcional)'),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (widget.date != null) ...[
                      IconButton.outlined(
                        tooltip: 'Apagar',
                        onPressed: _delete,
                        style: IconButton.styleFrom(fixedSize: const Size(52, 52)),
                        icon: Icon(LucideIcons.trash2, color: context.colors.error, size: 20),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton(onPressed: _save, child: const Text('Guardar')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
