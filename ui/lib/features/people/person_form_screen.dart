import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../services/notification_service.dart';
import '../auth/auth_widgets.dart';
import 'birthday_picker.dart';

const _relationSuggestions = [
  'Mãe',
  'Pai',
  'Irmã',
  'Irmão',
  'Avó',
  'Avô',
  'Amiga',
  'Amigo',
  'Colega',
  'Namorado(a)',
  'Tia',
  'Tio',
  'Prima',
  'Primo',
];

class PersonFormScreen extends ConsumerStatefulWidget {
  const PersonFormScreen({super.key, this.personId});

  final String? personId;

  @override
  ConsumerState<PersonFormScreen> createState() => _PersonFormScreenState();
}

class _PersonFormScreenState extends ConsumerState<PersonFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _relation = TextEditingController();
  final _budget = TextEditingController();
  final _notes = TextEditingController();

  Person? _original;
  BirthDate? _date;
  String? _categoryId;
  bool _useDefaultReminders = true;
  Set<int> _reminders = {...kDefaultReminderDays};
  Uint8List? _newPhoto;
  bool _removePhoto = false;
  bool _saving = false;
  bool _dateError = false;

  bool get _isEdit => widget.personId != null;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _reminders = {...?user?.defaultReminderDays};
    final p = widget.personId == null ? null : ref.read(dataProvider).person(widget.personId!);
    if (p != null) {
      _original = p;
      _name.text = p.name;
      _relation.text = p.relation;
      _notes.text = p.notes;
      _budget.text = p.giftBudget == null ? '' : _formatNumber(p.giftBudget!);
      _date = (day: p.day, month: p.month, year: p.year);
      _categoryId = p.categoryId;
      _useDefaultReminders = p.reminderDays == null;
      if (p.reminderDays != null) _reminders = {...p.reminderDays!};
    }
  }

  static String _formatNumber(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  void dispose() {
    _name.dispose();
    _relation.dispose();
    _budget.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final hasPhoto = _newPhoto != null || (!_removePhoto && _original?.photoUrl != null);
    final source = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.image),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: const Text('Tirar fotografia'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            if (hasPhoto)
              ListTile(
                leading: Icon(LucideIcons.trash2, color: ctx.colors.error),
                title: Text('Remover fotografia', style: TextStyle(color: ctx.colors.error)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    if (source == 'remove') {
      setState(() {
        _newPhoto = null;
        _removePhoto = true;
      });
      return;
    }
    try {
      final file = await ImagePicker().pickImage(
        source: source as ImageSource,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 82,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _newPhoto = bytes;
        _removePhoto = false;
      });
    } catch (_) {
      if (mounted) showMessage(context, 'Não foi possível aceder às fotografias. Verifica as permissões.');
    }
  }

  Future<void> _pickDate() async {
    final picked = await showBirthdayPicker(context, initial: _date);
    if (picked != null) {
      setState(() {
        _date = picked;
        _dateError = false;
      });
    }
  }

  double? _parseBudget() {
    final t = _budget.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _save() async {
    final valid = _form.currentState!.validate();
    setState(() => _dateError = _date == null);
    if (!valid || _date == null) return;
    if (!_useDefaultReminders && _reminders.isEmpty) {
      showMessage(context, 'Escolhe pelo menos um lembrete ou usa as predefinições.');
      return;
    }

    final repo = ref.read(dataRepositoryProvider);
    if (repo == null) return;
    final isFirst = ref.read(dataProvider).people.isEmpty;
    final d = _date!;
    final base =
        _original ?? Person(id: const Uuid().v4(), name: '', day: d.day, month: d.month, createdAt: DateTime.now());
    final person = base.copyWith(
      name: _name.text.trim(),
      day: d.day,
      month: d.month,
      year: () => d.year,
      relation: _relation.text.trim(),
      categoryId: () => _categoryId,
      notes: _notes.text.trim(),
      giftBudget: _parseBudget,
      reminderDays: () => _useDefaultReminders ? null : (_reminders.toList()..sort()),
    );

    setState(() => _saving = true);
    final ok = await runGuarded(
      context,
      () => repo.savePerson(person, photo: _newPhoto, removePhoto: _removePhoto),
      success: _isEdit ? 'Alterações guardadas.' : '${person.firstName} foi adicionado(a).',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    if (isFirst) NotificationService.instance.requestPermission();
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final user = ref.watch(currentUserProvider);
    final previewPerson =
        (_original ?? Person(id: 'preview', name: _name.text, day: 1, month: 1, createdAt: DateTime.now())).copyWith(
          name: _name.text.isEmpty ? '?' : _name.text,
          categoryId: () => _categoryId,
          photoUrl: _removePhoto ? () => null : null,
        );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(LucideIcons.x), onPressed: () => context.pop()),
        title: Text(_isEdit ? 'Editar pessoa' : 'Novo aniversário'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
              child: _saving
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Stack(
                  children: [
                    _newPhoto != null
                        ? ClipOval(child: Image.memory(_newPhoto!, width: 104, height: 104, fit: BoxFit.cover))
                        : PersonAvatar(person: previewPerson, color: personColor(previewPerson, data), size: 104),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: context.colors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.colors.surface, width: 3),
                        ),
                        child: Icon(LucideIcons.camera, size: 16, color: context.colors.onPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            const FieldLabel('Nome'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              validator: (v) => Validators.required(v, 'Indica o nome.'),
              decoration: const InputDecoration(hintText: 'Ex.: Ana Silva'),
            ),
            const SizedBox(height: 20),
            const FieldLabel('Data de aniversário'),
            _DateField(date: _date, error: _dateError, onTap: _pickDate),
            const SizedBox(height: 20),
            const FieldLabel('Relação'),
            TextFormField(
              controller: _relation,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Ex.: Mãe, amigo de infância, colega…'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in _relationSuggestions)
                  ChoiceChip(
                    label: Text(r),
                    selected: _relation.text == r,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _relation.text = r),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FieldLabel(
              'Categoria',
              trailing: GestureDetector(
                onTap: () => context.push('/profile/categories'),
                child: Text(
                  'Gerir',
                  style: context.text.labelMedium?.copyWith(color: context.colors.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in data.categories)
                  ChoiceChip(
                    avatar: CircleAvatar(radius: 5, backgroundColor: swatch(c.color)),
                    label: Text(c.name),
                    selected: _categoryId == c.id,
                    onSelected: (s) => setState(() => _categoryId = s ? c.id : null),
                  ),
                if (data.categories.isEmpty)
                  Text('Sem categorias.', style: TextStyle(color: context.palette.mutedForeground)),
              ],
            ),
            const SizedBox(height: 24),
            const FieldLabel('Lembretes'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Usar as minhas predefinições'),
                    subtitle: Text(
                      (user?.defaultReminderDays ?? kDefaultReminderDays).map(reminderLabel).join(', '),
                      style: TextStyle(color: context.palette.mutedForeground),
                    ),
                    value: _useDefaultReminders,
                    onChanged: (v) => setState(() => _useDefaultReminders = v),
                  ),
                  if (!_useDefaultReminders)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final d in kReminderOptions)
                          FilterChip(
                            label: Text(reminderLabel(d)),
                            selected: _reminders.contains(d),
                            onSelected: (s) => setState(() => s ? _reminders.add(d) : _reminders.remove(d)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const FieldLabel('Orçamento para presente'),
            TextFormField(
              controller: _budget,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              validator: (v) => (v != null && v.trim().isNotEmpty && _parseBudget() == null) ? 'Valor inválido.' : null,
              decoration: const InputDecoration(
                hintText: 'Opcional',
                prefixIcon: Icon(LucideIcons.wallet, size: 18),
                suffixText: '€',
              ),
            ),
            const SizedBox(height: 20),
            const FieldLabel('Notas'),
            TextFormField(
              controller: _notes,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Gostos, tamanhos, alergias, ideias…'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.error, required this.onTap});

  final BirthDate? date;
  final bool error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = date;
    final age = d?.year == null ? null : BirthdayUtils.turningAge(d!.day, d.month, d.year);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: context.palette.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: error ? context.colors.error : context.palette.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Icon(LucideIcons.cake, size: 18, color: context.palette.mutedForeground),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      d == null ? 'Escolher data' : Fmt.birthDate(d.day, d.month, d.year),
                      style: context.text.bodyLarge?.copyWith(
                        color: d == null ? context.palette.mutedForeground.withValues(alpha: 0.7) : null,
                      ),
                    ),
                  ),
                  if (age != null) Pill(label: 'Faz $age'),
                  const SizedBox(width: 4),
                  Icon(LucideIcons.chevronDown, size: 18, color: context.palette.mutedForeground),
                ],
              ),
            ),
          ),
        ),
        if (error)
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 6),
            child: Text(
              'Escolhe a data de aniversário.',
              style: context.text.bodySmall?.copyWith(color: context.colors.error),
            ),
          ),
      ],
    );
  }
}
