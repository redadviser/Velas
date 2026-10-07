import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/identity.dart';
import '../../core/widgets/common.dart';
import '../../data/models/group_models.dart';
import 'invite_links.dart';

/// Procura uma conta por email, telemóvel ou username e executa [onAction]
/// com a conta encontrada. [onAction] devolve a mensagem a mostrar.
class ContactLookup extends ConsumerStatefulWidget {
  const ContactLookup({super.key, required this.actionLabel, required this.onAction, this.onShareLink});

  final String actionLabel;
  final Future<String> Function(FoundUser user) onAction;

  /// Alternativa sugerida quando a conta não existe.
  final VoidCallback? onShareLink;

  @override
  ConsumerState<ContactLookup> createState() => _ContactLookupState();
}

class _ContactLookupState extends ConsumerState<ContactLookup> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  FoundUser? _found;
  String? _notFound;
  String? _feedback;
  bool _feedbackOk = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final kind = Identity.kindOf(_ctrl.text);
    setState(() {
      _found = null;
      _notFound = null;
      _feedback = null;
    });
    if (kind == IdentifierKind.invalid) {
      setState(() => _feedback = 'Escreve um email, um telemóvel (ex.: 912 345 678) ou um @username.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final user = await ref.read(groupRepositoryProvider)!.findUser(Identity.normalizeIdentifier(_ctrl.text)!);
      if (!mounted) return;
      setState(() {
        _found = user;
        if (user == null) {
          _notFound = switch (kind) {
            IdentifierKind.email => 'Não existe nenhuma conta com este email.',
            IdentifierKind.phone => 'Não existe nenhuma conta com este número de telemóvel.',
            _ => 'Não existe nenhuma conta com este username.',
          };
        }
      });
    } catch (e) {
      if (mounted) setState(() => _feedback = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(FoundUser user) async {
    setState(() => _busy = true);
    try {
      final message = await widget.onAction(user);
      if (!mounted) return;
      setState(() {
        _feedback = message;
        _feedbackOk = true;
        _found = null;
        _ctrl.clear();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _feedback = friendlyError(e);
          _feedbackOk = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final found = _found;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                onChanged: (_) {
                  if (_found != null || _notFound != null || _feedback != null) {
                    setState(() {
                      _found = null;
                      _notFound = null;
                      _feedback = null;
                    });
                  }
                },
                decoration: const InputDecoration(
                  hintText: 'Email, telemóvel ou @user',
                  prefixIcon: Icon(LucideIcons.search, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _search,
              style: FilledButton.styleFrom(
                minimumSize: const Size(56, 52),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: _busy && found == null
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Procurar'),
            ),
          ],
        ),
        if (found != null) ...[
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: context.palette.accent,
                  child: Text(
                    found.name.isEmpty ? '?' : found.name[0].toUpperCase(),
                    style: TextStyle(color: context.palette.accentForeground, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(found.name, style: context.text.titleSmall),
                      if (found.username.isNotEmpty)
                        Text(
                          '@${found.username}',
                          style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                        ),
                    ],
                  ),
                ),
                if (found.userId == me?.id)
                  const Pill(label: 'És tu')
                else
                  FilledButton(
                    onPressed: _busy ? null : () => _act(found),
                    style: FilledButton.styleFrom(minimumSize: const Size(92, 42)),
                    child: Text(widget.actionLabel),
                  ),
              ],
            ),
          ),
        ],
        if (_notFound != null) ...[
          const SizedBox(height: 12),
          AppCard(
            color: context.palette.muted,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.userX, size: 18, color: context.palette.mutedForeground),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_notFound!, style: context.text.titleSmall)),
                  ],
                ),
                if (widget.onShareLink != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Envia-lhe o link de convite: depois de criar conta, entra diretamente no grupo.',
                    style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: widget.onShareLink,
                    icon: const Icon(LucideIcons.share2, size: 16),
                    label: const Text('Partilhar link de convite'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (_feedback != null)
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 4),
            child: Row(
              children: [
                Icon(
                  _feedbackOk ? LucideIcons.circleCheck : LucideIcons.info,
                  size: 16,
                  color: _feedbackOk ? context.palette.success : context.palette.mutedForeground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _feedback!,
                    style: context.text.bodySmall?.copyWith(
                      color: _feedbackOk ? context.palette.success : context.palette.mutedForeground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String inviteResultMessage(InviteResult r, String name) => switch (r) {
  InviteResult.invited => 'Convite enviado a $name. Aparece-lhe na app para aceitar.',
  InviteResult.alreadyInvited => '$name já tem um convite pendente.',
  InviteResult.alreadyMember => '$name já está no grupo.',
  InviteResult.groupClosed => 'O grupo já fechou: a prenda foi comprada.',
  InviteResult.notFound => 'Esta conta já não existe.',
};

/// Folha "Convidar" do grupo: link de convite + procurar por contacto.
Future<void> showInviteSheet(BuildContext context, GiftGroup group) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _InviteSheet(group: group),
);

class _InviteSheet extends ConsumerWidget {
  const _InviteSheet({required this.group});

  final GiftGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void share() => SharePlus.instance.share(ShareParams(text: InviteLinks.shareText(group)));
    final link = InviteLinks.shareLink(group.inviteCode);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Convidar para o grupo', style: AppTheme.display(context, size: 22)),
              const SizedBox(height: 20),
              Text('Com um link', style: context.text.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Quem abrir o link entra no grupo — se ainda não tiver conta, cria uma primeiro.',
                style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                decoration: BoxDecoration(color: context.palette.muted, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
                    ),
                    IconButton(
                      tooltip: 'Copiar link',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: link));
                        if (context.mounted) showMessage(context, 'Link copiado.');
                      },
                      icon: const Icon(LucideIcons.copy, size: 18),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: share,
                icon: const Icon(LucideIcons.share2, size: 18),
                label: const Text('Partilhar link'),
              ),
              const SizedBox(height: 28),
              Text('Por email, telemóvel ou username', style: context.text.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Se a pessoa já tiver conta, recebe o convite na app.',
                style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
              ),
              const SizedBox(height: 10),
              ContactLookup(
                actionLabel: 'Convidar',
                onShareLink: share,
                onAction: (user) async {
                  String message = '';
                  await ref.read(groupsProvider.notifier).mutate((repo) async {
                    final r = await repo.inviteUser(group.id, user.userId);
                    message = inviteResultMessage(r, user.name);
                  });
                  return message;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Convites recebidos: aceitar ou recusar.
class InvitationsInbox extends ConsumerWidget {
  const InvitationsInbox({super.key, this.onAccepted});

  final void Function(String groupId)? onAccepted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitations = ref.watch(invitationsProvider).value ?? const [];
    if (invitations.isEmpty) return const SizedBox.shrink();

    Future<void> respond(InvitationPreview inv, bool accept) async {
      String? gid;
      final ok = await runGuarded(
        context,
        () => ref.read(groupsProvider.notifier).mutate((repo) async {
          gid = await repo.respondInvitation(inv.id, accept: accept);
        }),
        success: accept ? null : 'Convite recusado.',
      );
      ref.invalidate(invitationsProvider);
      if (ok && accept && gid != null) onAccepted?.call(gid!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text('Convites', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        for (final inv in invitations)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: AppCard(
              color: context.palette.accent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${inv.inviterName.isEmpty ? 'Alguém' : inv.inviterName} convidou-te',
                    style: context.text.labelMedium?.copyWith(color: context.palette.accentForeground),
                  ),
                  const SizedBox(height: 2),
                  Text(inv.title, style: AppTheme.display(context, size: 19, color: context.palette.accentForeground)),
                  Text(
                    '${inv.celebrantName} · ${inv.memberCount} ${inv.memberCount == 1 ? 'pessoa' : 'pessoas'}',
                    style: context.text.bodySmall?.copyWith(
                      color: context.palette.accentForeground.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => respond(inv, false),
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                          child: const Text('Recusar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => respond(inv, true),
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                          child: const Text('Aceitar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
