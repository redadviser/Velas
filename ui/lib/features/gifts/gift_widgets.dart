import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Linha de uma ideia de presente com caixa para marcar como comprado.
class GiftRow extends ConsumerWidget {
  const GiftRow({super.key, required this.gift, this.padding = const EdgeInsets.symmetric(horizontal: 12)});

  final GiftIdea gift;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = context.palette.mutedForeground;
    return InkWell(
      onTap: () => showGiftEditor(context, ref, personId: gift.personId, gift: gift),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Checkbox(
              value: gift.purchased,
              activeColor: context.palette.success,
              onChanged: (v) => runGuarded(
                context,
                () => ref.read(dataRepositoryProvider)!.saveGift(gift.copyWith(purchased: v ?? false)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gift.title,
                      style: context.text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        decoration: gift.purchased ? TextDecoration.lineThrough : null,
                        color: gift.purchased ? muted : null,
                      ),
                    ),
                    if (gift.notes.isNotEmpty || gift.link.isNotEmpty)
                      Text(
                        gift.notes.isNotEmpty ? gift.notes : gift.link,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(color: muted),
                      ),
                  ],
                ),
              ),
            ),
            if (gift.link.isNotEmpty) Icon(LucideIcons.link, size: 14, color: muted),
            if (gift.price != null) ...[
              const SizedBox(width: 8),
              Text(
                Fmt.money(gift.price!),
                style: context.text.labelLarge?.copyWith(color: gift.purchased ? muted : null),
              ),
            ],
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// Barra de orçamento: comprado vs. planeado vs. limite.
class BudgetBar extends StatelessWidget {
  const BudgetBar({super.key, required this.budget, required this.gifts});

  final double? budget;
  final List<GiftIdea> gifts;

  @override
  Widget build(BuildContext context) {
    final spent = gifts.where((g) => g.purchased).fold<double>(0, (a, g) => a + (g.price ?? 0));
    final planned = gifts.fold<double>(0, (a, g) => a + (g.price ?? 0));
    final limit = budget;
    final over = limit != null && spent > limit;
    final ratio = limit == null || limit == 0 ? 0.0 : (spent / limit).clamp(0.0, 1.0);
    final plannedRatio = limit == null || limit == 0 ? 0.0 : (planned / limit).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(Fmt.money(spent), style: AppTheme.display(context, size: 24)),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                limit == null ? 'gastos' : 'de ${Fmt.money(limit)}',
                style: TextStyle(color: context.palette.mutedForeground),
              ),
            ),
            const Spacer(),
            if (over)
              Pill(
                label: 'Acima do orçamento',
                background: context.colors.error.withValues(alpha: 0.12),
                foreground: context.colors.error,
              )
            else if (limit != null)
              Text(
                'Restam ${Fmt.money(limit - spent)}',
                style: context.text.labelMedium?.copyWith(color: context.palette.mutedForeground),
              ),
          ],
        ),
        if (limit != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: context.palette.muted),
                  FractionallySizedBox(
                    widthFactor: plannedRatio,
                    child: Container(color: context.colors.primary.withValues(alpha: 0.25)),
                  ),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(color: over ? context.colors.error : context.colors.primary),
                  ),
                ],
              ),
            ),
          ),
          if (planned > spent) ...[
            const SizedBox(height: 6),
            Text(
              'Ideias planeadas: ${Fmt.money(planned)}',
              style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
            ),
          ],
        ],
      ],
    );
  }
}

Future<void> showGiftEditor(BuildContext context, WidgetRef ref, {required String personId, GiftIdea? gift}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _GiftEditor(personId: personId, gift: gift),
  );
}

/// Escolhe uma pessoa e abre o editor (usado no separador Presentes).
Future<void> pickPersonThenAddGift(BuildContext context, WidgetRef ref) async {
  final data = ref.read(dataProvider);
  if (data.people.isEmpty) {
    showMessage(context, 'Adiciona primeiro uma pessoa.');
    return;
  }
  final person = await showModalBottomSheet<Person>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (ctx, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Presente para quem?', style: AppTheme.display(ctx, size: 22)),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              children: [
                for (final p in data.upcoming) PersonTile(person: p, data: data, onTap: () => Navigator.pop(ctx, p)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  if (person != null && context.mounted) await showGiftEditor(context, ref, personId: person.id);
}

class _GiftEditor extends ConsumerStatefulWidget {
  const _GiftEditor({required this.personId, this.gift});

  final String personId;
  final GiftIdea? gift;

  @override
  ConsumerState<_GiftEditor> createState() => _GiftEditorState();
}

class _GiftEditorState extends ConsumerState<_GiftEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.gift?.title);
  late final _price = TextEditingController(
    text: widget.gift?.price == null
        ? ''
        : widget.gift!.price!.toStringAsFixed(widget.gift!.price! % 1 == 0 ? 0 : 2).replaceAll('.', ','),
  );
  late final _link = TextEditingController(text: widget.gift?.link);
  late final _notes = TextEditingController(text: widget.gift?.notes);
  late bool _purchased = widget.gift?.purchased ?? false;

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _link.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? get _priceValue {
    final t = _price.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final repo = ref.read(dataRepositoryProvider)!;
    final base =
        widget.gift ?? GiftIdea(id: const Uuid().v4(), personId: widget.personId, title: '', createdAt: DateTime.now());
    final gift = base.copyWith(
      title: _title.text.trim(),
      price: () => _priceValue,
      link: _link.text.trim(),
      notes: _notes.text.trim(),
      purchased: _purchased,
    );
    final nav = Navigator.of(context);
    final ok = await runGuarded(context, () => repo.saveGift(gift));
    if (ok) nav.pop();
  }

  Future<void> _delete() async {
    final nav = Navigator.of(context);
    final ok = await runGuarded(
      context,
      () => ref.read(dataRepositoryProvider)!.deleteGift(widget.gift!.id),
      success: 'Ideia removida.',
    );
    if (ok) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final person = ref.watch(dataProvider).person(widget.personId);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                  widget.gift == null ? 'Nova ideia de presente' : 'Editar presente',
                  style: AppTheme.display(context, size: 22),
                ),
                if (person != null)
                  Text('Para ${person.name}', style: TextStyle(color: context.palette.mutedForeground)),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _title,
                  autofocus: widget.gift == null,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => Validators.required(v, 'Descreve o presente.'),
                  decoration: const InputDecoration(hintText: 'O quê? Ex.: Livro do Saramago'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        validator: (v) => (v != null && v.trim().isNotEmpty && _priceValue == null) ? 'Inválido' : null,
                        decoration: const InputDecoration(hintText: 'Preço', suffixText: '€'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Material(
                        color: _purchased ? context.palette.success.withValues(alpha: 0.12) : context.palette.card,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: _purchased ? Colors.transparent : context.palette.border),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _purchased = !_purchased),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _purchased ? LucideIcons.circleCheck : LucideIcons.circle,
                                  size: 18,
                                  color: _purchased ? context.palette.success : context.palette.mutedForeground,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Comprado',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _purchased ? context.palette.success : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _link,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'Link (opcional)',
                    prefixIcon: Icon(LucideIcons.link, size: 16),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Notas (tamanho, cor, loja…)'),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (widget.gift != null) ...[
                      IconButton.outlined(
                        tooltip: 'Eliminar',
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
