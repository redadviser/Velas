import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../core/wishlist_providers.dart';
import '../../data/models/models.dart';
import '../auth/auth_widgets.dart';
import 'gift_suggestions.dart';
import '../../core/i18n/translations.dart';

/// Escolher gostos e hobbies (chips que se ligam e desligam).
class InterestPicker extends StatelessWidget {
  const InterestPicker({super.key, required this.selected, required this.onChanged});

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final i in Interest.values)
        FilterChip(
          avatar: Icon(
            i.icon,
            size: 16,
            color: selected.contains(i.key) ? context.colors.surface : context.palette.mutedForeground,
          ),
          showCheckmark: false,
          label: Text(i.label),
          selected: selected.contains(i.key),
          onSelected: (on) => onChanged(on ? [...selected, i.key] : selected.where((k) => k != i.key).toList()),
        ),
    ],
  );
}

/// Os gostos escolhidos, só para ver.
class InterestChips extends StatelessWidget {
  const InterestChips({super.key, required this.keys});

  final Iterable<String> keys;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [for (final i in Interest.fromKeys(keys)) Pill(label: i.label, icon: i.icon, dense: true)],
  );
}

/// Um desejo. Sem [onTap] (lista de um amigo), o link abre-se ao tocar.
class WishRow extends StatelessWidget {
  const WishRow({super.key, required this.item, this.onTap, this.trailing});

  final WishItem item;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.mutedForeground;
    final link = Uri.tryParse(item.link);
    final canOpen = link != null && link.hasScheme;
    return InkWell(
      onTap: onTap ?? (canOpen ? () => launchUrl(link, mode: LaunchMode.externalApplication) : null),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(LucideIcons.heart, size: 18, color: context.palette.accentForeground),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                  if (item.notes.isNotEmpty || item.link.isNotEmpty)
                    Text(
                      [
                        if (item.notes.isNotEmpty) item.notes,
                        if (canOpen) link.host.replaceFirst('www.', ''),
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(color: muted),
                    ),
                ],
              ),
            ),
            if (item.price != null) ...[
              const SizedBox(width: 8),
              Text(Fmt.money(item.price!), style: context.text.labelLarge),
            ],
            ?trailing,
            if (trailing == null) const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// Copia um desejo de um amigo para as minhas ideias de prenda para [person].
Future<bool> keepWishAsIdea(BuildContext context, WidgetRef ref, Person person, WishItem w) => runGuarded(
  context,
  () => ref
      .read(dataRepositoryProvider)!
      .saveGift(
        GiftIdea(
          id: const Uuid().v4(),
          personId: person.id,
          title: w.title,
          price: w.price,
          link: w.link,
          notes: w.notes,
          createdAt: DateTime.now(),
        ),
      ),
  success: context.tr('Guardado nas tuas ideias para {name}.', {'name': person.firstName}),
);

/// Botão "guardar nas minhas ideias" (ou o visto, se já lá estiver).
class KeepWishButton extends ConsumerWidget {
  const KeepWishButton({super.key, required this.person, required this.wish});

  final Person person;
  final WishItem wish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kept = ref
        .watch(dataProvider)
        .giftsFor(person.id)
        .any((g) => g.title.toLowerCase() == wish.title.toLowerCase());
    return kept
        ? Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              LucideIcons.check,
              size: 20,
              color: context.palette.success,
              semanticLabel: context.tr('Já está nas tuas ideias'),
            ),
          )
        : IconButton(
            tooltip: context.tr('Guardar nas minhas ideias'),
            onPressed: () => keepWishAsIdea(context, ref, person, wish),
            icon: Icon(LucideIcons.bookmarkPlus, color: context.colors.primary),
          );
  }
}

Future<void> showWishEditor(BuildContext context, {WishItem? item}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useRootNavigator: true,
  builder: (_) => _WishEditor(item: item),
);

class _WishEditor extends ConsumerStatefulWidget {
  const _WishEditor({this.item});

  final WishItem? item;

  @override
  ConsumerState<_WishEditor> createState() => _WishEditorState();
}

class _WishEditorState extends ConsumerState<_WishEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.item?.title);
  late final _price = TextEditingController(
    text: widget.item?.price == null
        ? ''
        : widget.item!.price!.toStringAsFixed(widget.item!.price! % 1 == 0 ? 0 : 2).replaceAll('.', ','),
  );
  late final _link = TextEditingController(text: widget.item?.link);
  late final _notes = TextEditingController(text: widget.item?.notes);

  @override
  void dispose() {
    for (final c in [_title, _price, _link, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final t = _price.text.trim().replaceAll(',', '.');
    final wish = WishItem(
      id: widget.item?.id ?? const Uuid().v4(),
      title: _title.text.trim(),
      price: t.isEmpty ? null : double.tryParse(t),
      link: _link.text.trim(),
      notes: _notes.text.trim(),
      createdAt: widget.item?.createdAt ?? DateTime.now(),
    );
    final nav = Navigator.of(context);
    if (await runGuarded(context, () => ref.read(myWishlistProvider.notifier).save(wish))) nav.pop();
  }

  Future<void> _delete() async {
    final nav = Navigator.of(context);
    final ok = await runGuarded(
      context,
      () => ref.read(myWishlistProvider.notifier).remove(widget.item!.id),
      success: context.tr('Desejo apagado.'),
    );
    if (ok) nav.pop();
  }

  @override
  Widget build(BuildContext context) => Padding(
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
                widget.item == null ? context.tr('Novo desejo') : context.tr('Editar desejo'),
                style: AppTheme.display(context, size: 22),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                autofocus: widget.item == null,
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => Validators.required(v, context.tr('O que gostavas de receber?')),
                decoration: InputDecoration(hintText: context.tr('Ex.: Edição ilustrada de "Dune"')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(hintText: context.tr('Preço aproximado (opcional)'), suffixText: '€'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _link,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: context.tr('Link (opcional)'),
                  prefixIcon: const Icon(LucideIcons.link, size: 16),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: context.tr('Tamanho, cor, edição… (opcional)')),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (widget.item != null) ...[
                    IconButton.outlined(
                      tooltip: context.tr('Apagar'),
                      onPressed: _delete,
                      style: IconButton.styleFrom(fixedSize: const Size(52, 52)),
                      icon: Icon(LucideIcons.trash2, color: context.colors.error, size: 20),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton(onPressed: _save, child: Text(context.tr('Guardar'))),
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
