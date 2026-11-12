import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/chat_providers.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/confetti.dart';
import '../../data/models/group_models.dart';
import '../../data/models/payment.dart';
import '../chat/chat_widgets.dart';
import 'group_widgets.dart';
import 'invite_widgets.dart';
import 'payment_widgets.dart';
import '../../core/constants.dart';
import '../../core/i18n/translations.dart';

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
    final paid = await showPaySheet(
      context,
      payeeName: g.buyer?.name ?? context.tr('quem compra'),
      amount: g.shareOf(me),
      payee: payee,
      reference: '${g.title}: ${me.name}',
    );
    if (paid == null || !context.mounted) return;
    final method = paid.method;
    final ok = await runGuarded(
      context,
      () => _ctrl(ref).mutate(
        (repo) => repo.setPaid(me, method),
        optimistic: _replace(g, me.copyWith(paidAt: () => DateTime.now(), paidMethod: () => method)),
      ),
      success: g.buyer == null
          ? context.tr('Registado. Quem compra vai confirmar que recebeu.')
          : context.tr('Registado. {name} vai confirmar que recebeu.', {'name': g.buyer!.name}),
    );
    if (ok && context.mounted) showConfetti(context);
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
        child: SingleChildScrollView(
          // Desliza quando não cabe (letra grande).
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
                  title: Text(ctx.tr('Confirmar que recebi')),
                  subtitle: Text(
                    m.paidMethod == null
                        ? ctx.tr('Por exemplo, se pagou em mão')
                        : ctx.tr('Pagou por {method}', {'method': m.paidMethod!.label}),
                  ),
                  onTap: () => Navigator.pop(ctx, 'confirm'),
                ),
              if (status == ContributionStatus.confirmed)
                ListTile(
                  leading: const Icon(LucideIcons.undo2),
                  title: Text(ctx.tr('Anular confirmação')),
                  onTap: () => Navigator.pop(ctx, 'unconfirm'),
                ),
              if (status == ContributionStatus.paid)
                ListTile(
                  leading: const Icon(LucideIcons.circleX),
                  title: Text(ctx.tr('Não recebi: voltar a "por pagar"')),
                  onTap: () => Navigator.pop(ctx, 'reset'),
                ),
              if (status == ContributionStatus.pending)
                ListTile(
                  leading: const Icon(LucideIcons.send),
                  title: Text(ctx.tr('Lembrar {name}', {'name': m.name})),
                  onTap: () => Navigator.pop(ctx, 'remind'),
                ),
              const SizedBox(height: 8),
            ],
          ),
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
        title: context.tr('Ainda faltam pagamentos'),
        message: context.tr('Há {count} participantes sem pagamento confirmado. Marcar mesmo assim como comprada?', {
          'count': g.pendingCount + g.awaitingConfirmationCount,
        }),
        confirm: context.tr('Marcar comprada'),
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
      success: purchased ? context.tr('Prenda comprada. Bom trabalho! 🎁') : null,
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
      title: asAdmin ? context.tr('Eliminar grupo?') : context.tr('Sair do grupo?'),
      message: asAdmin
          ? context.tr('O grupo e os registos de pagamento são apagados para todos os participantes.')
          : context.tr('Deixas de ver este grupo. Se já pagaste, combina primeiro com quem compra.'),
      confirm: asAdmin ? context.tr('Eliminar') : context.tr('Sair'),
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
            : EmptyState(
                icon: LucideIcons.usersRound,
                title: context.tr('Grupo não encontrado'),
                message: context.tr('Pode ter sido eliminado pelo administrador.'),
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
          if (g.conversationId != null)
            IconButton(
              tooltip: context.tr(Keys.chatGroupCardTitle),
              onPressed: () => context.push('/chats/${g.conversationId}'),
              icon: Badge(
                isLabelVisible: ref.watch(groupUnreadProvider(g.conversationId!)) > 0,
                label: Text('${ref.watch(groupUnreadProvider(g.conversationId!))}'),
                child: const Icon(LucideIcons.messageCircle, size: 20),
              ),
            ),
          if (isAdmin)
            IconButton(
              tooltip: context.tr('Editar'),
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
                    Text(
                      isAdmin ? ctx.tr('Eliminar grupo') : ctx.tr('Sair do grupo'),
                      style: TextStyle(color: ctx.colors.error),
                    ),
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
            _Header(group: g, canEditPhoto: isAdmin && supportsInvites),
            if (g.conversationId != null) ...[
              const SizedBox(height: 12),
              _GroupChatCard(conversationId: g.conversationId!),
            ],
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
            // Quem compra e ainda não disse para onde quer receber: pergunta-se aqui.
            if (iAmBuyer && g.purchasedAt == null && payee.hasValue && !payee.value!.hasAnyDigital)
              _ReceivePrompt(
                onTap: () => context.push('/profile/payments').then((_) => ref.invalidate(_payeeProvider(groupId))),
              ),
            if (buyer != null)
              _BuyerCard(
                buyer: buyer,
                isMe: iAmBuyer,
                payee: payee.value,
                missingPayee: payee.hasValue && !payee.value!.hasAnyDigital,
                // Quem compra (eu) já tem o _ReceivePrompt; o administrador indica os dados de quem não tem conta.
                onAddPayment: isAdmin && buyer.userId == null ? () => context.push('/groups/${g.id}/edit') : null,
              ),
            if (supportsInvites && g.inviteCode.isNotEmpty && g.purchasedAt == null) ...[
              const SizedBox(height: 12),
              InviteCodeCard(group: g, onInviteContact: isAdmin ? () => showInviteSheet(context, g) : null),
            ],
            SectionTitle(
              context.tr('Participantes · {count}', {'count': g.members.length}),
              action: canManage && pending.isNotEmpty ? context.tr('Lembrar quem falta') : null,
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
                              success: context.tr('Convite cancelado.'),
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
                  context.tr('Toca num participante para confirmar que recebeste.'),
                  style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                ),
              ),
            if (canManage) ...[
              const SizedBox(height: 24),
              g.purchasedAt == null
                  ? FilledButton.icon(
                      onPressed: () => _togglePurchased(context, ref, g),
                      icon: const Icon(LucideIcons.shoppingBag, size: 18),
                      label: Text(context.tr('Marcar prenda como comprada')),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => _togglePurchased(context, ref, g),
                      icon: const Icon(LucideIcons.undo2, size: 18),
                      label: Text(context.tr('Ainda não foi comprada')),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Atalho para a conversa do grupo, com a última mensagem.
class _GroupChatCard extends ConsumerWidget {
  const _GroupChatCard({required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(conversationsProvider).value?.where((x) => x.id == conversationId).firstOrNull;
    final me = ref.watch(currentUserProvider)?.id;
    final last = c?.lastMessage;
    return AppCard(
      onTap: () => context.push('/chats/$conversationId'),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: context.palette.accent,
            child: Icon(LucideIcons.messagesSquare, size: 18, color: context.palette.accentForeground),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr(Keys.chatGroupCardTitle), style: context.text.titleSmall),
                Text(
                  last == null
                      ? context.tr(Keys.chatGroupCardEmpty)
                      : last.senderId == me
                      ? context.tr(Keys.chatPreviewYou, {'text': last.preview})
                      : context.tr(Keys.chatPreviewSender, {
                          'name': last.senderName.split(' ').first,
                          'text': last.preview,
                        }),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if ((c?.unreadCount ?? 0) > 0)
            CountBadge(count: c!.unreadCount)
          else
            Icon(LucideIcons.chevronRight, size: 18, color: context.palette.mutedForeground),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.group, this.canEditPhoto = false});

  final GiftGroup group;
  final bool canEditPhoto;

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
                  label: context.tr('Comprada'),
                  background: context.palette.success.withValues(alpha: 0.14),
                  foreground: context.palette.success,
                )
              else if (g.deadline != null)
                Pill(
                  icon: LucideIcons.clock,
                  label: context.tr('Pagar até {date}', {'date': Fmt.dayMonth(g.deadline!)}),
                  background: context.palette.card,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _GroupPhoto(group: g, editable: canEditPhoto),
              const SizedBox(width: 14),
              Expanded(child: Text(g.title, style: AppTheme.display(context, size: 26))),
            ],
          ),
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
                    Flexible(
                      child: Text(
                        context.tr('Ver prenda'),
                        style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
          // Wrap: com letra grande, "de X recebidos" passa para baixo.
          Text(context.tr('JÁ REUNIMOS'), style: AppTheme.eyebrow(context)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    Text(Fmt.money(g.confirmedAmount), style: AppTheme.display(context, size: 30)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        context.tr('de {amount}', {'amount': Fmt.money(g.targetAmount)}),
                        style: TextStyle(color: context.palette.mutedForeground),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(ratio * 100).round()}%',
                style: AppTheme.display(context, size: 20, color: context.palette.accentForeground),
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
                    child: Container(color: context.colors.primary.withValues(alpha: 0.25)),
                  ),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        gradient: context.palette.brand,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('{paid} de {total} pessoas já pagaram', {
              'paid': g.members.where((m) => g.statusOf(m) == ContributionStatus.confirmed).length,
              'total': g.members.length,
            }),
            style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
          ),
          if (g.awaitingConfirmationCount > 0) ...[
            const SizedBox(height: 2),
            Text(
              g.awaitingConfirmationCount == 1
                  ? context.tr('1 pagamento por confirmar')
                  : context.tr('{count} pagamentos por confirmar', {'count': g.awaitingConfirmationCount}),
              style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
            ),
          ],
          if (g.splitMode == SplitMode.custom && g.unassigned.abs() >= 0.01) ...[
            const SizedBox(height: 6),
            Text(
              g.unassigned > 0
                  ? context.tr('Faltam distribuir {amount} pelos participantes.', {'amount': Fmt.money(g.unassigned)})
                  : context.tr('As partes excedem o total em {amount}.', {'amount': Fmt.money(-g.unassigned)}),
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
    final buyerName = group.buyer?.name ?? context.tr('quem compra');

    return AppCard(
      child: switch (status) {
        ContributionStatus.pending => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('A tua parte'),
              style: context.text.labelLarge?.copyWith(color: context.palette.mutedForeground),
            ),
            Text(Fmt.money(share), style: AppTheme.display(context, size: 34)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: share > 0 ? onPay : null,
              icon: const Icon(LucideIcons.send, size: 18),
              label: Text(context.tr('Pagar a {name}', {'name': buyerName})),
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
                    me.paidMethod == null
                        ? context.tr('Pagaste {amount}', {'amount': Fmt.money(share)})
                        : context.tr('Pagaste {amount} por {method}', {
                            'amount': Fmt.money(share),
                            'method': me.paidMethod!.label,
                          }),
                    style: context.text.titleSmall,
                  ),
                  Text(
                    context.tr('A aguardar que {name} confirme.', {'name': buyerName}),
                    style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onUndo, child: Text(context.tr('Anular'))),
          ],
        ),
        ContributionStatus.confirmed => Row(
          children: [
            Icon(LucideIcons.circleCheck, color: context.palette.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.tr('A tua parte de {amount} está paga e confirmada.', {'amount': Fmt.money(share)}),
                style: context.text.titleSmall,
              ),
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
                      isMe
                          ? context.tr('Tu compras a prenda')
                          : context.tr('{name} compra a prenda', {'name': buyer.name}),
                      style: context.text.titleSmall,
                    ),
                    Text(
                      isMe ? context.tr('Os outros pagam-te a ti.') : context.tr('É a quem os outros pagam.'),
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
              children: [for (final m in methods) Pill(leading: PaymentLogo(m, size: 14), label: m.label, dense: true)],
            ),
          ],
          if (missingPayee && onAddPayment != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAddPayment,
              icon: const Icon(LucideIcons.wallet, size: 18),
              label: Text(isMe ? context.tr(Keys.receiveAction) : context.tr('Indicar dados de pagamento')),
            ),
          ],
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
                  [
                    if (invitation.username.isNotEmpty) '@${invitation.username}',
                    context.tr('Convite pendente'),
                  ].join(' · '),
                  style: context.text.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          if (onCancel != null)
            IconButton(
              tooltip: context.tr('Cancelar convite'),
              onPressed: onCancel,
              icon: Icon(LucideIcons.x, size: 18, color: muted),
            ),
        ],
      ),
    );
  }
}

/// Fotografia do grupo; o administrador toca para escolher, tirar ou remover.
class _GroupPhoto extends ConsumerStatefulWidget {
  const _GroupPhoto({required this.group, required this.editable});

  final GiftGroup group;
  final bool editable;

  @override
  ConsumerState<_GroupPhoto> createState() => _GroupPhotoState();
}

class _GroupPhotoState extends ConsumerState<_GroupPhoto> {
  bool _busy = false;

  Future<void> _change() async {
    final g = widget.group;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          // Desliza quando não cabe (letra grande).
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(ctx.tr(Keys.groupPhotoChange), style: AppTheme.display(ctx, size: 22)),
              ),
              ListTile(
                leading: const Icon(LucideIcons.images),
                title: Text(ctx.tr(Keys.commonGallery)),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              ListTile(
                leading: const Icon(LucideIcons.camera),
                title: Text(ctx.tr(Keys.commonCamera)),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              if (g.photoUrl != null)
                ListTile(
                  leading: Icon(LucideIcons.trash2, color: ctx.colors.error),
                  title: Text(ctx.tr(Keys.groupPhotoRemove), style: TextStyle(color: ctx.colors.error)),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;

    Uint8List? bytes;
    if (action != 'remove') {
      try {
        // Pequena: só aparece em avatares (até 2 MB no servidor).
        final picked = await pickChatImage(action == 'camera' ? ImageSource.camera : ImageSource.gallery, maxSide: 640);
        if (picked == null) return;
        bytes = picked.bytes;
      } catch (_) {
        if (mounted) showMessage(context, context.tr(Keys.commonPhotosPermission));
        return;
      }
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final photo = bytes;
    await runGuarded(context, () async {
      await ref.read(groupsProvider.notifier).mutate((repo) => repo.setGroupPhoto(g.id, photo));
      // A conversa do grupo também mostra a fotografia.
      await ref.read(conversationsProvider.notifier).refresh().catchError((_) {});
    }, success: context.tr(photo == null ? Keys.groupPhotoRemoved : Keys.groupPhotoUpdated));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    final avatar = GroupAvatar(
      photoUrl: widget.group.photoUrl,
      size: size,
      purchased: widget.group.purchasedAt != null,
    );
    if (!widget.editable) return avatar;
    return Semantics(
      button: true,
      label: context.tr(Keys.groupPhotoChange),
      child: GestureDetector(
        onTap: _busy ? null : _change,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            if (_busy)
              const Positioned.fill(
                child: ClipOval(
                  child: ColoredBox(
                    color: Color(0x66000000),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.colors.surface, width: 2),
                ),
                child: Icon(LucideIcons.camera, size: 13, color: context.colors.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Para onde queres receber?": quem compra a prenda ainda não indicou como quer receber.
class _ReceivePrompt extends StatelessWidget {
  const _ReceivePrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = context.palette.accentForeground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        color: context.palette.accent,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const PaymentLogo(PaymentMethod.mbway, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(context.tr(Keys.receiveTitle), style: context.text.titleSmall?.copyWith(color: fg)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(context.tr(Keys.receiveHint), style: context.text.bodySmall?.copyWith(color: fg)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(LucideIcons.wallet, size: 18),
              label: Text(context.tr(Keys.receiveAction)),
            ),
          ],
        ),
      ),
    );
  }
}
