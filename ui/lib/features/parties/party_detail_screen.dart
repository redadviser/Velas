import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/text.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/confetti.dart';
import '../../data/models/party_models.dart';
import 'party_widgets.dart';

class PartyDetailScreen extends ConsumerWidget {
  const PartyDetailScreen({super.key, required this.partyId});

  final String partyId;

  PartiesController _ctrl(WidgetRef ref) => ref.read(partiesProvider.notifier);

  Future<void> _share(Party p) => SharePlus.instance.share(
    ShareParams(
      text:
          'Estamos a preparar uma surpresa para ${p.celebrantName}! Entra na festa na Birthdayly com o código ${p.inviteCode}. Não digas nada!',
    ),
  );

  Future<void> _addGuest(BuildContext context, WidgetRef ref, Party p) async {
    final name = await _askText(
      context,
      title: 'Convidado sem conta',
      hint: 'Nome (ex.: Tia Rosa)',
      action: 'Acrescentar',
    );
    if (name == null || !context.mounted) return;
    await runGuarded(context, () => _ctrl(ref).run((repo) => repo.addGuest(p.id, name)));
  }

  Future<void> _task(BuildContext context, WidgetRef ref, Party p, {PartyTask? task}) async {
    final result = await showModalBottomSheet<PartyTask>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TaskSheet(party: p, task: task),
    );
    if (result == null || !context.mounted) return;
    await runGuarded(context, () => _ctrl(ref).run((repo) => repo.saveTask(p.id, result)));
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, Party p, String action) async {
    final router = GoRouter.of(context);
    switch (action) {
      case 'edit':
        router.push('/parties/${p.id}/edit');
      case 'delete':
        final sure = await confirmDialog(
          context,
          title: 'Apagar a festa?',
          message: 'Os convidados deixam de a ver. Não dá para desfazer.',
        );
        if (!sure) return;
        if (!context.mounted) return;
        if (await runGuarded(
          context,
          () => _ctrl(ref).run((repo) async {
            await repo.deleteParty(p.id);
            return null;
          }),
        )) {
          router.pop();
        }
      case 'leave':
        final me = p.guestFor(ref.read(currentUserProvider)?.id);
        if (me == null) return;
        if (!await confirmDialog(
          context,
          title: 'Sair da festa?',
          message: 'Deixas de a ver. Podes voltar com o código.',
          confirm: 'Sair',
        )) {
          return;
        }
        if (!context.mounted) return;
        if (await runGuarded(
          context,
          () => _ctrl(ref).run((repo) async {
            await repo.removeGuest(me.id);
            return null;
          }),
        )) {
          router.pop();
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(partiesProvider);
    final p = async.value?.where((x) => x.id == partyId).firstOrNull;
    final userId = ref.watch(currentUserProvider)?.id;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
            : const EmptyState(
                icon: LucideIcons.partyPopper,
                title: 'Festa não encontrada',
                message: 'Pode ter sido apagada por quem a organiza.',
              ),
      );
    }
    final host = p.isHost(userId);
    final me = p.guestFor(userId);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(tooltip: 'Convidar', icon: const Icon(LucideIcons.share2, size: 20), onPressed: () => _share(p)),
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.ellipsisVertical, size: 20),
            onSelected: (v) => _menu(context, ref, p, v),
            itemBuilder: (_) => [
              if (host) const PopupMenuItem(value: 'edit', child: Text('Editar')),
              if (host) const PopupMenuItem(value: 'delete', child: Text('Apagar festa')),
              if (!host) const PopupMenuItem(value: 'leave', child: Text('Sair da festa')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _ctrl(ref).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            _Cover(party: p),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: context.palette.violetSoft, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Icon(LucideIcons.lock, size: 16, color: context.colors.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Secreto: só quem foi convidado vê esta festa.',
                      style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            if (me != null) ...[
              SectionTitle('Vais?', padding: const EdgeInsets.fromLTRB(4, 24, 0, 10)),
              Row(
                children: [
                  for (final r in [Rsvp.yes, Rsvp.maybe, Rsvp.no]) ...[
                    if (r != Rsvp.yes) const SizedBox(width: 8),
                    Expanded(
                      child: _RsvpButton(
                        rsvp: r,
                        selected: me.rsvp == r,
                        onTap: () async {
                          final ok = await runGuarded(context, () => _ctrl(ref).run((repo) => repo.rsvp(p.id, r)));
                          if (ok && r == Rsvp.yes && context.mounted) showConfetti(context);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ],
            SectionTitle(
              'Convidados · ${p.guests.length}',
              action: host ? 'Acrescentar' : null,
              onAction: () => _addGuest(context, ref, p),
              padding: const EdgeInsets.fromLTRB(4, 24, 0, 6),
            ),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, g) in p.guests.indexed) ...[
                    if (i > 0) const Divider(indent: 64),
                    _GuestRow(
                      guest: g,
                      isHost: g.userId == p.createdBy,
                      onRemove: host && g.userId != p.createdBy
                          ? () => runGuarded(
                              context,
                              () => _ctrl(ref).run((repo) async {
                                await repo.removeGuest(g.id);
                                return null;
                              }),
                            )
                          : null,
                    ),
                  ],
                  const Divider(),
                  ListTile(
                    onTap: () => _share(p),
                    leading: const IconBadge(icon: LucideIcons.ticket, size: 38),
                    title: const Text('Convidar com o código'),
                    subtitle: Text(p.inviteCode, style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.w700)),
                    trailing: IconButton(
                      tooltip: 'Copiar código',
                      icon: const Icon(LucideIcons.copy, size: 18),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: p.inviteCode));
                        if (context.mounted) showMessage(context, 'Código copiado.');
                      },
                    ),
                  ),
                ],
              ),
            ),
            SectionTitle(
              p.tasks.isEmpty ? 'Tarefas' : 'Tarefas · ${p.doneTasks} de ${p.tasks.length}',
              action: 'Nova',
              onAction: () => _task(context, ref, p),
              padding: const EdgeInsets.fromLTRB(4, 24, 0, 6),
            ),
            if (p.tasks.isNotEmpty) ...[
              SoftProgress(value: p.doneTasks / p.tasks.length, semanticsLabel: 'Tarefas feitas'),
              const SizedBox(height: 10),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, t) in p.tasks.indexed) ...[
                      if (i > 0) const Divider(indent: 56),
                      _TaskRow(
                        task: t,
                        assignee: p.guest(t.assigneeId),
                        onToggle: () => runGuarded(
                          context,
                          () => _ctrl(ref).run((repo) => repo.saveTask(p.id, t.copyWith(done: !t.done))),
                        ),
                        onEdit: () => _task(context, ref, p, task: t),
                      ),
                    ],
                  ],
                ),
              ),
            ] else
              DashedButton(
                icon: LucideIcons.listTodo,
                label: 'Bolo, balões, quem leva o aniversariante…',
                onTap: () => _task(context, ref, p),
              ),
            if (p.notes.isNotEmpty) ...[
              SectionTitle('Notas', padding: const EdgeInsets.fromLTRB(4, 24, 0, 10)),
              AppCard(child: Text(p.notes, style: context.text.bodyMedium)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Capa violeta com o título, a data e a contagem de respostas.
class _Cover extends StatelessWidget {
  const _Cover({required this.party});

  final Party party;

  @override
  Widget build(BuildContext context) {
    final p = party;
    const white = Colors.white;
    final days = p.startsAt == null
        ? null
        : DateUtils.dateOnly(p.startsAt!).difference(DateUtils.dateOnly(DateTime.now())).inDays;
    Widget stat(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(value, style: AppTheme.display(context, size: 20, color: white)),
          Text(label, style: context.text.labelSmall?.copyWith(color: white)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6650CC), Color(0xFF8B4FC4)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
            child: Text(
              days == null || days < 0
                  ? 'FESTA SURPRESA'
                  : days == 0
                  ? 'É HOJE'
                  : days == 1
                  ? 'É AMANHÃ'
                  : 'FALTAM $days DIAS',
              style: AppTheme.eyebrow(context, color: white).copyWith(fontSize: 10),
            ),
          ),
          const SizedBox(height: 14),
          Text(p.title, style: AppTheme.display(context, size: 25, color: white)),
          const SizedBox(height: 4),
          Text('Para ${p.celebrantName}', style: context.text.bodyMedium?.copyWith(color: white)),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(LucideIcons.calendarClock, size: 16, color: white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(partyWhen(p), style: context.text.bodySmall?.copyWith(color: white)),
              ),
            ],
          ),
          if (p.place.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(LucideIcons.mapPin, size: 16, color: white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(p.place, style: context.text.bodySmall?.copyWith(color: white)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                stat('${p.count(Rsvp.yes)}', 'vão'),
                stat('${p.count(Rsvp.maybe)}', 'talvez'),
                stat('${p.count(Rsvp.pending)}', 'por responder'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RsvpButton extends StatelessWidget {
  const _RsvpButton({required this.rsvp, required this.selected, required this.onTap});

  final Rsvp rsvp;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = rsvpColors(context, rsvp);
    final label = switch (rsvp) {
      Rsvp.yes => 'Vou',
      Rsvp.maybe => 'Talvez',
      Rsvp.no => 'Não vou',
      Rsvp.pending => '',
    };
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? bg : context.palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? fg : context.palette.border, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: context.text.labelLarge?.copyWith(
                  color: selected ? fg : context.colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuestRow extends StatelessWidget {
  const _GuestRow({required this.guest, required this.isHost, this.onRemove});

  final PartyGuest guest;
  final bool isHost;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = rsvpColors(context, guest.rsvp);
    final tone = AppColors.tones[guest.name.codeUnits.fold<int>(0, (a, b) => a + b) % AppColors.tones.length];
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 14, right: 6),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: tone.$1,
        child: Text(initialOf(guest.name), style: AppTheme.display(context, size: 15, color: tone.$2)),
      ),
      title: Text(guest.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (isHost) 'Organiza',
          if (guest.userId == null) 'Sem conta' else if (guest.username != null) '@${guest.username}',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Pill(label: guest.rsvp.label, background: bg, foreground: fg, dense: true),
          if (onRemove != null)
            IconButton(
              tooltip: 'Tirar da festa',
              icon: Icon(LucideIcons.x, size: 18, color: context.palette.mutedForeground),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.assignee, required this.onToggle, required this.onEdit});

  final PartyTask task;
  final PartyGuest? assignee;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.mutedForeground;
    return ListTile(
      onTap: onEdit,
      contentPadding: const EdgeInsets.only(left: 6, right: 14),
      leading: Checkbox(value: task.done, onChanged: (_) => onToggle(), semanticLabel: task.title),
      title: Text(
        task.title,
        style: task.done
            ? TextStyle(color: muted, decoration: TextDecoration.lineThrough, decorationColor: muted)
            : null,
      ),
      subtitle: Text(
        assignee == null ? 'Sem responsável' : assignee!.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _TaskSheet extends StatefulWidget {
  const _TaskSheet({required this.party, this.task});

  final Party party;
  final PartyTask? task;

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late final _title = TextEditingController(text: widget.task?.title);
  late String? _assignee = widget.task?.assigneeId;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _save() {
    final t = _title.text.trim();
    if (t.isEmpty) return;
    final base = widget.task ?? PartyTask(id: const Uuid().v4(), title: t);
    Navigator.pop(context, base.copyWith(title: t, assigneeId: () => _assignee));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.task == null ? 'Nova tarefa' : 'Editar tarefa', style: AppTheme.display(context, size: 22)),
              const SizedBox(height: 14),
              TextField(
                controller: _title,
                autofocus: widget.task == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Ex.: Encomendar o bolo'),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 14),
              Text('Quem trata?', style: context.text.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Ninguém ainda'),
                    selected: _assignee == null,
                    onSelected: (_) => setState(() => _assignee = null),
                  ),
                  for (final g in widget.party.guests)
                    ChoiceChip(
                      label: Text(g.name),
                      selected: _assignee == g.id,
                      onSelected: (_) => setState(() => _assignee = g.id),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: const Text('Guardar')),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> _askText(BuildContext context, {required String title, required String hint, required String action}) =>
    showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: Text(title, style: AppTheme.display(ctx, size: 22)),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim().isEmpty ? null : c.text.trim()),
              style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
              child: Text(action),
            ),
          ],
        );
      },
    );
