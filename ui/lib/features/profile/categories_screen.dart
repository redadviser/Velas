import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';

/// Gerir categorias (Família, Amigos, Trabalho, …) — RF11.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [PersonCategory? category]) async {
    final data = ref.read(dataProvider);
    final result = await showModalBottomSheet<PersonCategory>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategoryEditor(category: category, nextSort: data.categories.length),
    );
    if (result != null && context.mounted) {
      await runGuarded(context, () => ref.read(dataRepositoryProvider)!.saveCategory(result));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, PersonCategory c, int count) async {
    final ok = await confirmDialog(
      context,
      title: 'Eliminar "${c.name}"?',
      message: count == 0
          ? 'A categoria vai ser removida.'
          : 'As $count pessoas desta categoria ficam sem categoria. Não são eliminadas.',
    );
    if (ok && context.mounted) {
      await runGuarded(context, () => ref.read(dataRepositoryProvider)!.deleteCategory(c.id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Categorias')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(LucideIcons.plus, size: 20),
        label: const Text('Nova categoria'),
      ),
      body: data.categories.isEmpty
          ? const Center(
              child: EmptyState(
                icon: LucideIcons.tag,
                title: 'Sem categorias',
                message: 'Cria categorias para organizar as pessoas — por exemplo Família, Amigos ou Trabalho.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              children: [
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, c) in data.categories.indexed) ...[
                        if (i > 0) const Divider(indent: 16, endIndent: 16),
                        Builder(
                          builder: (context) {
                            final count = data.people.where((p) => p.categoryId == c.id).length;
                            return ListTile(
                              onTap: () => _edit(context, ref, c),
                              leading: CircleAvatar(radius: 8, backgroundColor: swatch(c.color)),
                              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(count == 1 ? '1 pessoa' : '$count pessoas'),
                              trailing: IconButton(
                                tooltip: 'Eliminar',
                                icon: Icon(LucideIcons.trash2, size: 18, color: context.palette.mutedForeground),
                                onPressed: () => _delete(context, ref, c, count),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({this.category, required this.nextSort});

  final PersonCategory? category;
  final int nextSort;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.category?.name);
  late int _color = widget.category?.color ?? widget.nextSort % AppColors.swatches.length;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final c =
        widget.category?.copyWith(name: name, color: _color) ??
        PersonCategory(id: const Uuid().v4(), name: name, color: _color, sort: widget.nextSort);
    Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.category == null ? 'Nova categoria' : 'Editar categoria',
              style: AppTheme.display(context, size: 22),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(hintText: 'Ex.: Ginásio, Faculdade…'),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < AppColors.swatches.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _color = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 40,
                      height: 40,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _color == i ? swatch(i) : Colors.transparent, width: 2),
                      ),
                      child: Container(
                        decoration: BoxDecoration(color: swatch(i), shape: BoxShape.circle),
                        child: _color == i ? const Icon(LucideIcons.check, color: Colors.white, size: 18) : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _name.text.trim().isEmpty ? null : _submit, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}
