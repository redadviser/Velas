import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/env.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/utils/errors.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../services/contacts_import.dart';
import '../auth/auth_widgets.dart';

/// Importa aniversários dos contactos do telemóvel (iPhone/iCloud, Android)
/// ou do Google Contacts. Nada é guardado sem a pessoa confirmar.
class ImportContactsScreen extends ConsumerStatefulWidget {
  const ImportContactsScreen({super.key});

  @override
  ConsumerState<ImportContactsScreen> createState() => _ImportContactsScreenState();
}

class _ImportContactsScreenState extends ConsumerState<ImportContactsScreen> {
  ContactSource? _loading;
  ContactSource? _source;
  ContactScan? _scan;
  final _selected = <String>{};
  String? _categoryId;
  bool _importing = false;

  Future<void> _load(ContactSource source) async {
    setState(() => _loading = source);
    try {
      final scan = switch (source) {
        ContactSource.device => await ContactsImporter.fromDevice(),
        ContactSource.google => await ContactsImporter.fromGoogle(),
      };
      final existing = ContactCandidate.keysOf(ref.read(dataProvider).people);
      setState(() {
        _source = source;
        _scan = scan;
        _selected
          ..clear()
          ..addAll([
            for (final c in scan.candidates)
              if (!c.isIn(existing)) c.key,
          ]);
      });
    } on SilentException {
      // Cancelado pela pessoa.
    } on ContactsPermissionException catch (e) {
      if (mounted) _showPermissionDialog(e.message);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }

  void _showPermissionDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Acesso aos contactos', style: AppTheme.display(ctx, size: 22)),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Agora não')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ContactsImporter.openSettings();
            },
            child: const Text('Abrir Definições'),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final scan = _scan;
    final repo = ref.read(dataRepositoryProvider);
    if (scan == null || repo == null) return;
    final chosen = scan.candidates.where((c) => _selected.contains(c.key)).toList();
    if (chosen.isEmpty) return;

    setState(() => _importing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final people = <Person>[];
      final photos = <String, Uint8List>{};
      for (final c in chosen) {
        final person = c.toPerson(categoryId: _categoryId);
        people.add(person);
        if (c.photo != null) photos[person.id] = c.photo!;
      }
      // Fotografias do Google: descarregadas agora, poucas de cada vez.
      final remote = [
        for (var i = 0; i < chosen.length; i++)
          if (chosen[i].photoUrl != null) (people[i].id, chosen[i].photoUrl!),
      ];
      for (var i = 0; i < remote.length; i += 6) {
        await Future.wait([
          for (final (id, url) in remote.skip(i).take(6))
            ContactsImporter.downloadPhoto(url).then((bytes) {
              if (bytes != null) photos[id] = bytes;
            }),
        ]);
      }
      await repo.importPeople(people, photos: photos);
      if (!mounted) return;
      context.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            people.length == 1 ? '1 aniversário importado.' : '${people.length} aniversários importados.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        showMessage(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    return PopScope(
      canPop: !_importing,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: _importing
                ? null
                : () => scan == null
                      ? context.pop()
                      : setState(() {
                          _scan = null;
                          _source = null;
                        }),
          ),
          title: const Text('Importar contactos'),
        ),
        body: scan == null ? _SourcePicker(loading: _loading, onPick: _load) : _buildList(context, scan),
        bottomNavigationBar: scan == null || scan.candidates.isEmpty
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: LoadingButton(
                  label: _selected.isEmpty
                      ? 'Escolhe quem importar'
                      : _selected.length == 1
                      ? 'Importar 1 aniversário'
                      : 'Importar ${_selected.length} aniversários',
                  icon: LucideIcons.download,
                  loading: _importing,
                  onPressed: _selected.isEmpty ? null : _import,
                ),
              ),
      ),
    );
  }

  Widget _buildList(BuildContext context, ContactScan scan) {
    final data = ref.watch(dataProvider);
    final existing = ContactCandidate.keysOf(data.people);
    final available = scan.candidates.where((c) => !c.isIn(existing)).toList();
    final allSelected = available.isNotEmpty && available.every((c) => _selected.contains(c.key));
    final sourceName = _source == ContactSource.google ? 'Google' : _deviceTitle;

    if (scan.candidates.isEmpty) {
      return EmptyState(
        icon: LucideIcons.calendarX2,
        title: 'Nenhum aniversário encontrado',
        message: scan.withoutBirthday == 0
            ? 'Não encontrámos contactos em $sourceName.'
            : 'Os ${scan.withoutBirthday} contactos de $sourceName não têm data de aniversário. '
                  'Podes acrescentá-la na app de Contactos e voltar a importar.',
        action: OutlinedButton(
          onPressed: () => setState(() => _scan = null),
          child: const Text('Escolher outra origem'),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text(
            [
              '${scan.candidates.length} com aniversário em $sourceName',
              if (scan.withoutBirthday > 0) '${scan.withoutBirthday} sem data (ignorados)',
            ].join(' · '),
            style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground),
          ),
        ),
        if (data.categories.isNotEmpty) ...[
          const SectionTitle('Categoria', padding: EdgeInsets.fromLTRB(20, 16, 12, 8)),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _CategoryChip(
                  label: 'Sem categoria',
                  selected: _categoryId == null,
                  onTap: () => setState(() => _categoryId = null),
                ),
                for (final c in data.categories)
                  _CategoryChip(
                    label: c.name,
                    color: swatch(c.color),
                    selected: _categoryId == c.id,
                    onTap: () => setState(() => _categoryId = c.id),
                  ),
              ],
            ),
          ),
        ],
        SectionTitle(
          'Contactos',
          action: available.isEmpty ? null : (allSelected ? 'Limpar' : 'Selecionar todos'),
          onAction: () => setState(() {
            if (allSelected) {
              _selected.clear();
            } else {
              _selected.addAll(available.map((c) => c.key));
            }
          }),
        ),
        for (final c in scan.candidates)
          _CandidateTile(
            candidate: c,
            duplicate: c.isIn(existing),
            selected: _selected.contains(c.key),
            onChanged: _importing
                ? null
                : (v) => setState(() => v ? _selected.add(c.key) : _selected.remove(c.key)),
          ),
      ],
    );
  }
}

String get _deviceTitle => Platform.isIOS ? 'iPhone e iCloud' : 'Contactos do telemóvel';

class _SourcePicker extends StatelessWidget {
  const _SourcePicker({required this.loading, required this.onPick});

  final ContactSource? loading;
  final ValueChanged<ContactSource> onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('Traz os aniversários que já tens guardados', style: AppTheme.display(context, size: 26)),
        const SizedBox(height: 8),
        Text(
          'Escolhe de onde importar. Mostramos a lista antes de guardar e só entram as pessoas que escolheres.',
          style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground, fontSize: 15),
        ),
        const SizedBox(height: 24),
        _SourceCard(
          icon: LucideIcons.smartphone,
          title: _deviceTitle,
          subtitle: Platform.isIOS
              ? 'Os contactos do iPhone, incluindo os sincronizados com o iCloud.'
              : 'Inclui os contactos das contas Google sincronizadas neste telemóvel.',
          loading: loading == ContactSource.device,
          enabled: loading == null,
          onTap: () => onPick(ContactSource.device),
        ),
        const SizedBox(height: 12),
        _SourceCard(
          leading: const GoogleLogo(size: 22),
          title: 'Google Contacts',
          subtitle: Env.hasGoogle
              ? 'Entra com a tua conta Google e importa os aniversários dos teus contactos.'
              : 'Disponível quando o Google estiver configurado nesta versão da app.',
          loading: loading == ContactSource.google,
          enabled: loading == null && Env.hasGoogle,
          onTap: () => onPick(ContactSource.google),
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.shieldCheck, size: 18, color: context.palette.mutedForeground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Só lemos o nome, a data de aniversário e a fotografia. Os contactos sem data de aniversário são ignorados.',
                style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    this.icon,
    this.leading,
    required this.title,
    required this.subtitle,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  final IconData? icon;
  final Widget? leading;
  final String title;
  final String subtitle;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled || loading ? 1 : 0.55,
      child: AppCard(
        onTap: enabled ? onTap : null,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: context.palette.softGradient, borderRadius: BorderRadius.circular(14)),
              child: leading ?? Icon(icon, color: context.colors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            loading
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                : Icon(LucideIcons.chevronRight, size: 18, color: context.palette.mutedForeground),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap, this.color});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: color == null ? null : CircleAvatar(backgroundColor: color, radius: 5),
      showCheckmark: false,
    ),
  );
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.duplicate,
    required this.selected,
    required this.onChanged,
  });

  final ContactCandidate candidate;
  final bool duplicate;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final ImageProvider? image = c.photo != null
        ? MemoryImage(c.photo!)
        : c.photoUrl != null
        ? NetworkImage(c.photoUrl!)
        : null;
    final initials = c.name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).take(2).map((s) => s[0]).join();

    return Opacity(
      opacity: duplicate ? 0.5 : 1,
      child: CheckboxListTile(
        value: duplicate ? false : selected,
        onChanged: duplicate || onChanged == null ? null : (v) => onChanged!(v ?? false),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        secondary: CircleAvatar(
          radius: 22,
          backgroundColor: context.palette.accent,
          foregroundImage: image,
          child: Text(
            initials.toUpperCase(),
            style: TextStyle(color: context.palette.accentForeground, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [Fmt.birthDate(c.day, c.month, c.year), if (duplicate) 'Já está na tua lista'].join(' · '),
          style: TextStyle(color: context.palette.mutedForeground),
        ),
      ),
    );
  }
}

/// Atalho bem visível para a importação (Início e Pessoas).
class ImportContactsCard extends StatelessWidget {
  const ImportContactsCard({super.key, this.onDismiss});

  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.push('/import'),
        child: Ink(
          decoration: BoxDecoration(
            gradient: context.palette.softGradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.palette.border),
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(14)),
                child: const Icon(LucideIcons.contactRound, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Importa os teus contactos',
                      style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Traz os aniversários do iPhone, Android ou Google em segundos.',
                      style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                    ),
                  ],
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  tooltip: 'Esconder',
                  onPressed: onDismiss,
                  icon: Icon(LucideIcons.x, size: 18, color: context.palette.mutedForeground),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(LucideIcons.chevronRight, size: 18, color: context.palette.mutedForeground),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
