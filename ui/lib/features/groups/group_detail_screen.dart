import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/models/group_models.dart';
import '../../data/models/payment.dart';
import 'group_widgets.dart';
import 'invite_links.dart';
import 'invite_widgets.dart';
import 'payment_widgets.dart';

/// Dados de pagamento do comprador (pedidos ao servidor só a membros).
final _payeeProvider = FutureProvider.autoDispose.family<PaymentDetails, String>((ref, groupId) async {
  final group = ref.watch(groupsProvider).value?.where((g) => g.id == groupId).firstOrNull;
  final repo = ref.watch(groupRepositoryProvider);
  if (group == null || repo == null) return PaymentDetails.empty;
  return repo.fetchPayee(group);
});

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  GroupsController _ctrl(WidgetRef ref) => ref.read(groupsProvider.notifier);

  Future<void> _pay(BuildContext context, WidgetRef ref, GiftGroup g, GroupMember me) async {
    final payee = await ref.read(_payeeProvider(groupId).future);
    if (!context.mounted) return;
    final method = await showPaySheet(
      context,
      payeeName: g.buyer?.name ?? 'quem compra',
      amount: g.shareOf(me),
      payee: payee,
      reference: '${g.title} — ${me.name}',
    );
    if (method == null || !context.mounted) return;
    await runGuarded(
      context,
      () => _ctrl(ref).mutate(
        (repo) => repo.setPaid(me, method),
        optimistic: _replace(g, me.copyWith(paidAt: () => DateTime.now(), paidMethod: () => method)),
      ),
      success: 'Registado. ${g.buyer?.name ?? 'Quem compra'} vai confirmar que recebeu.',
    );
  }

  GiftGroup _replace(GiftGroup g, GroupMember m) =>
      g.copyWith(members: [for (final x in g.members) x.id == m.id ? m : x]);

  Future<void> _memberActions(
    BuildContext context,
    WidgetRef ref,
    GiftGroup g,
    GroupMember m, {
    required bool canManage,
  }) async {
    final status = g.statusOf(m);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${m.name} · ${Fmt.money(g.shareOf(m))}', style: AppTheme.display(ctx, size: 20)),
              ),
            ),
            if (status != ContributionStatus.confirmed)
              ListTile(
                leading: const Icon(LucideIcons.circleCheck),
                title: const Text('Confirmar que recebi'),
                subtitle: Text(
                  m.paidMethod == null ? 'Por exemplo, se pagou em mão' : 'Pagou por ${m.paidMethod!.label}',
                ),
                onTap: () => Navigator.pop(ctx, 'confirm'),
              ),
            if (status == ContributionStatus.confirmed)
              ListTile(
                leading: const Icon(LucideIcons.undo2),
                title: const Text('Anular confirmação'),
                onTap: () => Navigator.pop(ctx, 'unconfirm'),
              ),
            if (status == ContributionStatus.paid)
              ListTile(
                leading: const Icon(LucideIcons.circleX),
                title: const Text('Não recebi — voltar a "por pagar"'),
                onTap: () => Navigator.pop(ctx, 'reset'),
              ),
            if (status == ContributionStatus.pending)
              ListTile(
                leading: const Icon(LucideIcons.send),
                title: Text('Lembrar ${m.name}'),
                onTap: () => Navigator.pop(ctx, 'remind'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final now = DateTime.now();
    switch (action) {
      case 'confirm':
        await runGuarded(
          context,
          () => _ctrl(ref).mutate(
            (repo) => repo.setConfirmed(m, true),
            optimistic: _replace(
              g,
              m.copyWith(
                confirmedAt: () => now,
                paidAt: m.paidAt == null ? () => now : null,
                paidMethod: m.paidAt == null ? () => PaymentMethod.cash : null,
              ),
            ),
          ),
        );
      case 'unconfirm':
        await runGuarded(
          context,
          () => _ctrl(
            ref,
          ).mutate((repo) => repo.setConfirmed(m, false), optimistic: _replace(g, m.copyWith(confirmedAt: () => null))),
        );
      case 'reset':
        await runGuarded(
          context,
          () => _ctrl(ref).mutate(
            (repo) => repo.setPaid(m, null),
            optimistic: _replace(g, m.copyWith(paidAt: () => null, paidMethod: () => null, confirmedAt: () => null)),
          ),
        );
      case 'remind':
        await SharePlus.instance.share(ShareParams(text: reminderText(g, [m])));
    }
  }

  Future<void> _togglePurchased(BuildContext context, WidgetRef ref, GiftGroup g) async {
    final purchased = g.purchasedAt == null;
    if (purchased && !g.fullyCollected) {
      final ok = await confirmDialog(
        context,
        title: 'Ainda faltam pagamentos',
        message:
            'Há ${g.pendingCount + g.awaitingConfirmationCount} participantes sem pagamento confirmado. Marcar mesmo assim como comprada?',
        confirm: 'Marcar comprada',
        destructive: false,
      );
      if (!ok || !context.mounted) return;
    }
    await runGuarded(
      context,
      () => _ctrl(ref).mutate(
        (repo) => repo.setPurchased(g.id, purchased),
        optimistic: g.copyWith(purchasedAt: () => purchased ? DateTime.now() : null),
      ),
      success: purchased ? 'Prenda comprada. Bom trabalho! 🎁' : null,
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    GiftGroup g, {
    required bool asAdmin,
    GroupMember? me,
  }) async {
    final ok = await confirmDialog(
      context,
      title: asAdmin ? 'Eliminar grupo?' : 'Sair do grupo?',
      message: asAdmin
          ? 'O grupo e os registos de pagamento são apagados para todos os participantes.'
          : 'Deixas de ver este grupo. Se já pagaste, combina primeiro com quem compra.',
      confirm: asAdmin ? 'Eliminar' : 'Sair',
    );
    if (!ok || !context.mounted) return;
    final router = GoRouter.of(context);
    final done = await runGuarded(
      context,
      () => _ctrl(ref).mutate((repo) => asAdmin ? repo.deleteGroup(g.id) : repo.removeMember(me!)),
    );
    if (done) router.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final groupsAsync = ref.watch(groupsProvider);
    final g = groupsAsync.value?.where((x) => x.id == groupId).firstOrNull;
    final supportsInvites = ref.watch(groupRepositoryProvider)?.supportsInvites ?? false;

    if (g == null) {
      return Scaffold(
        appBar: AppBar(),
        body: groupsAsync.isLoading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
            : const EmptyState(
                icon: LucideIcons.usersRound,
                title: 'Grupo não encontrado',
                message: 'Pode ter sido eliminado pelo administrador.',
              ),
      );
    }

    final isAdmin = g.isAdminUser(user?.id);
    final me = g.memberFor(user?.id);
    final buyer = g.buyer;
    final iAmBuyer = buyer != null && me != null && buyer.id == me.id;
    final canManage = isAdmin || iAmBuyer;
    final payee = ref.watch(_payeeProvider(groupId));
    final pending = g.sortedMembers.where((m) => g.statusOf(m) == ContributionStatus.pending).toList();

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(LucideIcons.pencil, size: 20),
              onPressed: () => context.push('/groups/${g.id}/edit'),
            ),
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.ellipsisVertical, size: 20),
            onSelected: (v) => switch (v) {
              'delete' => _delete(context, ref, g, asAdmin: true),
              'leave' => _delete(context, ref, g, asAdmin: false, me: me),
              _ => null,
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: isAdmin ? 'delete' : 'leave',
                child: Row(
                  children: [
                    Icon(isAdmin ? LucideIcons.trash2 : LucideIcons.logOut, size: 18, color: ctx.colors.error),
                    const SizedBox(width: 12),
                    Text(isAdmin ? 'Eliminar grupo' : 'Sair do grupo', style: TextStyle(color: ctx.colors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _ctrl(ref).refresh();
          ref.invalidate(_payeeProvider(groupId));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            _Header(group: g),
            const SizedBox(height: 16),
            if (me != null && !iAmBuyer) ...[
              _MyShare(
                group: g,
                me: me,
                onPay: () => _pay(context, ref, g, me),
                onUndo: () {
                  runGuarded(
                    context,
                    () => _ctrl(ref).mutate(
                      (repo) => repo.setPaid(me, null),
                      optimistic: _replace(g, me.copyWith(paidAt: () => null, paidMethod: () => null)),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
            if (buyer != null)
              _BuyerCard(
                buyer: buyer,
                isMe: iAmBuyer,
                payee: payee.value,
                missingPayee: payee.hasValue && !payee.value!.hasAnyDigital,
                onAddPayment: iAmBuyer
                    ? () => context.push('/profile/payments').then((_) => ref.invalidate(_payeeProvider(groupId)))
                    : isAdmin && buyer.userId == null
                    ? () => context.push('/groups/${g.id}/edit')
                    : null,
              ),
            if (supportsInvites && g.inviteCode.isNotEmpty && g.purchasedAt == null) ...[
              const SizedBox(height: 12),
              _InviteCard(group: g, isAdmin: isAdmin),
            ],
            SectionTitle(
              'Participantes · ${g.members.length}',
              action: canManage && pending.isNotEmpty ? 'Lembrar quem falta' : null,
              onAction: () => SharePlus.instance.share(ShareParams(text: reminderText(g, pending))),
              padding: const EdgeInsets.fromLTRB(4, 24, 0, 8),
            ),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, m) in g.sortedMembers.indexed) ...[
                    if (i > 0) const Divider(indent: 16, endIndent: 16),
                    MemberRow(
                      group: g,
                      member: m,
                      index: i,
                      isMe: m.id == me?.id,
                      onTap: canManage && !g.isBuyer(m)
                          ? () => _memberActions(context, ref, g, m, canManage: canManage)
                          : null,
                    ),
                  ],
                  for (final inv in g.invitations) ...[
                    const Divider(indent: 16, endIndent: 16),
                    _PendingInviteRow(
                      invitation: inv,
                      onCancel: isAdmin
                          ? () => runGuarded(
                              context,
                              () => _ctrl(ref).mutate(
                                (repo) => repo.cancelInvitation(inv),
                                optimistic: g.copyWith(
                                  invitations: g.invitations.where((i) => i.id != inv.id).toList(),
                                ),
                              ),
                              success: 'Convite cancelado.',
                            )
                          : null,
                    ),
                  ],
                ],
              ),
            ),
            if (canManage && g.awaitingConfirmationCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  'Toca num participante para confirmar que recebeste.',
                  style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                ),
              ),
            if (canManage) ...[
              const SizedBox(height: 24),
              g.purchasedAt == null
                  ? FilledButton.icon(
                      onPressed: () => _togglePurchased(context, ref, g),
                      icon: const Icon(LucideIcons.shoppingBag, size: 18),
                      label: const Text('Marcar prenda como comprada'),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => _togglePurchased(context, ref, g),
                      icon: const Icon(LucideIcons.undo2, size: 18),
                      label: const Text('Ainda não foi comprada'),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.group});

  final GiftGroup group;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final next = g.nextBirthday;
    final ratio = g.targetAmount == 0 ? 0.0 : (g.confirmedAmount / g.targetAmount).clamp(0.0, 1.0);
    final reportedRatio = g.targetAmount == 0 ? 0.0 : (g.reportedAmount / g.targetAmount).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: context.palette.softGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill(
                icon: LucideIcons.cake,
                label: next == null ? g.celebrantName : '${g.celebrantName} · ${Fmt.dayMonth(next)}',
                background: context.palette.card,
              ),
              if (g.purchasedAt != null)
                Pill(
                  icon: LucideIcons.circleCheck,
                  label: 'Comprada',
                  background: context.palette.success.withValues(alpha: 0.14),
                  foreground: context.palette.success,
                )
              else if (g.deadline != null)
                Pill(
                  icon: LucideIcons.clock,
                  label: 'Pagar até ${Fmt.dayMonth(g.deadline!)}',
                  background: context.palette.card,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(g.title, style: AppTheme.display(context, size: 26)),
          if (g.giftDescription.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(g.giftDescription, style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground)),
          ],
          if (g.giftLink.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                onTap: () {
                  final uri = Uri.tryParse(g.giftLink.startsWith('http') ? g.giftLink : 'https://${g.giftLink}');
                  if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.externalLink, size: 14, color: context.colors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Ver prenda',
                      style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.money(g.confirmedAmount), style: AppTheme.display(context, size: 30)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'de ${Fmt.money(g.targetAmount)} recebidos',
                  style: TextStyle(color: context.palette.mutedForeground),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Container(color: context.palette.card),
                  FractionallySizedBox(
                    widthFactor: reportedRatio,
                    child: Container(color: context.palette.success.withValues(alpha: 0.3)),
                  ),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(color: context.palette.success),
                  ),
                ],
              ),
            ),
          ),
          if (g.awaitingConfirmationCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${g.awaitingConfirmationCount} pagamento${g.awaitingConfirmationCount == 1 ? '' : 's'} por confirmar',
              style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
            ),
          ],
          if (g.splitMode == SplitMode.custom && g.unassigned.abs() >= 0.01) ...[
            const SizedBox(height: 6),
            Text(
              g.unassigned > 0
                  ? 'Faltam distribuir ${Fmt.money(g.unassigned)} pelos participantes.'
                  : 'As partes excedem o total em ${Fmt.money(-g.unassigned)}.',
              style: context.text.bodySmall?.copyWith(color: context.colors.error, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

class _MyShare extends StatelessWidget {
  const _MyShare({required this.group, required this.me, required this.onPay, required this.onUndo});

  final GiftGroup group;
  final GroupMember me;
  final VoidCallback onPay;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final share = group.shareOf(me);
    final status = group.statusOf(me);
    final buyerName = group.buyer?.name ?? 'quem compra';

    return AppCard(
      child: switch (status) {
        ContributionStatus.pending => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('A tua parte', style: context.text.labelLarge?.copyWith(color: context.palette.mutedForeground)),
            Text(Fmt.money(share), style: AppTheme.display(context, size: 34)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: share > 0 ? onPay : null,
              icon: const Icon(LucideIcons.send, size: 18),
              label: Text('Pagar a $buyerName'),
            ),
          ],
        ),
        ContributionStatus.paid => Row(
          children: [
            Icon(LucideIcons.hourglass, color: context.palette.mutedForeground),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pagaste ${Fmt.money(share)}${me.paidMethod == null ? '' : ' por ${me.paidMethod!.label}'}',
                    style: context.text.titleSmall,
                  ),
                  Text(
                    'A aguardar que $buyerName confirme.',
                    style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onUndo, child: const Text('Anular')),
          ],
        ),
        ContributionStatus.confirmed => Row(
          children: [
            Icon(LucideIcons.circleCheck, color: context.palette.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text('A tua parte de ${Fmt.money(share)} está paga e confirmada.', style: context.text.titleSmall),
            ),
          ],
        ),
      },
    );
  }
}

class _BuyerCard extends StatelessWidget {
  const _BuyerCard({
    required this.buyer,
    required this.isMe,
    required this.payee,
    required this.missingPayee,
    this.onAddPayment,
  });

  final GroupMember buyer;
  final bool isMe;
  final PaymentDetails? payee;
  final bool missingPayee;
  final VoidCallback? onAddPayment;

  @override
  Widget build(BuildContext context) {
    final methods = payee?.methods ?? const [];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: context.palette.accent,
                child: Icon(LucideIcons.shoppingBag, size: 18, color: context.palette.accentForeground),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMe ? 'Tu compras a prenda' : '${buyer.name} compra a prenda',
                      style: context.text.titleSmall,
                    ),
                    Text(
                      isMe ? 'Os outros pagam-te a ti.' : 'É a quem os outros pagam.',
                      style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (methods.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final m in methods) Pill(icon: paymentIcon(m), label: m.label, dense: true)],
            ),
          ],
          if (missingPayee && onAddPayment != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAddPayment,
              icon: const Icon(LucideIcons.wallet, size: 18),
              label: Text(isMe ? 'Adicionar MB WAY / IBAN' : 'Indicar dados de pagamento'),
            ),
          ],
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.group, required this.isAdmin});

  final GiftGroup group;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: context.palette.accent,
            child: Icon(LucideIcons.userPlus, size: 18, color: context.palette.accentForeground),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Convidar pessoas', style: context.text.titleSmall),
                Text(
                  isAdmin ? 'Por link, email, telemóvel ou username' : 'Partilha o link do grupo',
                  style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                ),
              ],
            ),
          ),
          if (isAdmin)
            FilledButton(
              onPressed: () => showInviteSheet(context, group),
              style: FilledButton.styleFrom(minimumSize: const Size(96, 42)),
              child: const Text('Convidar'),
            )
          else
            IconButton.filled(
              tooltip: 'Partilhar link',
              onPressed: () => SharePlus.instance.share(ShareParams(text: InviteLinks.shareText(group))),
              icon: const Icon(LucideIcons.share2, size: 20),
            ),
        ],
      ),
    );
  }
}

class _PendingInviteRow extends StatelessWidget {
  const _PendingInviteRow({required this.invitation, this.onCancel});

  final GroupInvitation invitation;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.mutedForeground;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: context.palette.muted,
            child: Icon(LucideIcons.mail, size: 16, color: muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitation.name,
                  style: context.text.bodyLarge?.copyWith(color: muted, fontWeight: FontWeight.w600),
                ),
                Text(
                  [if (invitation.username.isNotEmpty) '@${invitation.username}', 'Convite pendente'].join(' · '),
                  style: context.text.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          if (onCancel != null)
            IconButton(
              tooltip: 'Cancelar convite',
              onPressed: onCancel,
              icon: Icon(LucideIcons.x, size: 18, color: muted),
            ),
        ],
      ),
    );
  }
}
