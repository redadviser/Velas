import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../data/models/group_models.dart';
import '../auth/auth_widgets.dart';
import 'invite_widgets.dart';

/// Mensagem para lembrar quem ainda não pagou.
String reminderText(GiftGroup g, List<GroupMember> pending) {
  final buyer = g.buyer?.name ?? 'quem compra';
  final lines = [for (final m in pending) '• ${m.name}: ${Fmt.money(g.shareOf(m))}'];
  return [
    'Olá! 🎁 Falta pouco para a prenda "${g.title}".',
    if (pending.length == 1) 'A tua parte é ${Fmt.money(g.shareOf(pending.first))}.' else ...['Ainda falta:', ...lines],
    'O pagamento é para $buyer${g.deadline == null ? '' : ' até ${Fmt.dayMonth(g.deadline!)}'}. Obrigado!',
  ].join('\n');
}

({String label, Color bg, Color fg}) statusStyle(BuildContext context, ContributionStatus s, {bool isBuyer = false}) {
  if (isBuyer) return (label: 'Compra', bg: context.palette.accent, fg: context.palette.accentForeground);
  return switch (s) {
    ContributionStatus.pending => (label: 'Por pagar', bg: context.palette.muted, fg: context.palette.mutedForeground),
    ContributionStatus.paid => (
      label: 'Por confirmar',
      bg: AppColors.amber.withValues(alpha: 0.16),
      fg: Color.lerp(AppColors.amber, context.colors.onSurface, 0.35)!,
    ),
    ContributionStatus.confirmed => (
      label: 'Pago',
      bg: context.palette.success.withValues(alpha: 0.14),
      fg: context.palette.success,
    ),
  };
}

class MemberRow extends StatelessWidget {
  const MemberRow({
    super.key,
    required this.group,
    required this.member,
    required this.index,
    required this.isMe,
    this.onTap,
  });

  final GiftGroup group;
  final GroupMember member;
  final int index;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isBuyer = group.isBuyer(member);
    final style = statusStyle(context, group.statusOf(member), isBuyer: isBuyer);
    final tags = [
      if (member.username.isNotEmpty) '@${member.username}',
      if (isMe) 'Tu',
      if (member.userId == group.createdBy) 'Administrador',
      if (!member.hasAccount) 'Sem conta',
      if (member.paidMethod != null && !isBuyer) member.paidMethod!.label,
    ];
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: swatch(index).withValues(alpha: 0.16),
              child: Text(
                member.name.isEmpty ? '?' : member.name[0].toUpperCase(),
                style: TextStyle(color: swatch(index), fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  if (tags.isNotEmpty)
                    Text(
                      tags.join(' · '),
                      style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Fmt.money(group.shareOf(member)), style: context.text.labelLarge),
                const SizedBox(height: 4),
                Pill(label: style.label, background: style.bg, foreground: style.fg, dense: true),
              ],
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronRight, size: 16, color: context.palette.mutedForeground),
            ],
          ],
        ),
      ),
    );
  }
}

/// Cartão de um grupo na lista.
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.group, required this.userId});

  final GiftGroup group;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final me = g.memberFor(userId);
    final iAmBuyer = me != null && g.isBuyer(me);
    final ratio = g.targetAmount == 0 ? 0.0 : (g.confirmedAmount / g.targetAmount).clamp(0.0, 1.0);
    final next = g.nextBirthday;

    final (String label, Color bg, Color fg) chip = g.purchasedAt != null
        ? ('Prenda comprada', context.palette.success.withValues(alpha: 0.14), context.palette.success)
        : iAmBuyer
        ? (
            g.awaitingConfirmationCount > 0 ? '${g.awaitingConfirmationCount} por confirmar' : 'Tu compras',
            context.palette.accent,
            context.palette.accentForeground,
          )
        : me == null
        ? ('', Colors.transparent, Colors.transparent)
        : switch (g.statusOf(me)) {
            ContributionStatus.pending => (
              'Pagar ${Fmt.money(g.shareOf(me))}',
              context.colors.primary,
              context.colors.onPrimary,
            ),
            ContributionStatus.paid => (
              'A confirmar',
              AppColors.amber.withValues(alpha: 0.16),
              Color.lerp(AppColors.amber, context.colors.onSurface, 0.35)!,
            ),
            ContributionStatus.confirmed => (
              'Pago',
              context.palette.success.withValues(alpha: 0.14),
              context.palette.success,
            ),
          };

    return AppCard(
      onTap: () => context.push('/groups/${g.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.title, style: AppTheme.display(context, size: 19)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (next != null) '${g.celebrantName} · ${Fmt.dayMonth(next)}' else g.celebrantName,
                        '${g.members.length} pessoas',
                      ].join(' · '),
                      style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                    ),
                  ],
                ),
              ),
              if (chip.$1.isNotEmpty) Pill(label: chip.$1, background: chip.$2, foreground: chip.$3),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              color: context.palette.success,
              backgroundColor: context.palette.muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${Fmt.money(g.confirmedAmount)} de ${Fmt.money(g.targetAmount)}',
            style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// Lista de grupos (separador "Em grupo" dos Presentes).
class GroupsList extends ConsumerWidget {
  const GroupsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(groupsProvider);
    final user = ref.watch(currentUserProvider);
    final supportsInvites = ref.watch(groupRepositoryProvider)?.supportsInvites ?? false;

    if (async.hasError && !async.hasValue) {
      return ErrorRetry(error: async.error!, onRetry: () => ref.invalidate(groupsProvider));
    }
    final groups = async.value;
    if (groups == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }

    final active = groups.where((g) => g.purchasedAt == null).toList();
    final done = groups.where((g) => g.purchasedAt != null).toList();

    final inbox = InvitationsInbox(onAccepted: (id) => context.push('/groups/$id'));

    if (groups.isEmpty) {
      return Column(
        children: [
          inbox,
          EmptyState(
            icon: LucideIcons.usersRound,
            title: 'Prendas em grupo',
            message:
                'Junta amigos ou família, combinem o valor de cada um e paguem diretamente a quem compra — por MB WAY, transferência ou em mão.',
            action: Column(
              children: [
                FilledButton.icon(
                  onPressed: () => context.push('/groups/new'),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: const Text('Criar grupo'),
                  style: FilledButton.styleFrom(minimumSize: const Size(240, 52)),
                ),
                if (supportsInvites) ...[
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => showJoinGroupSheet(context, ref), child: const Text('Tenho um código')),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        inbox,
        if (supportsInvites)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: OutlinedButton.icon(
              onPressed: () => showJoinGroupSheet(context, ref),
              icon: const Icon(LucideIcons.ticket, size: 18),
              label: const Text('Entrar com código'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            ),
          ),
        for (final g in active)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: GroupCard(group: g, userId: user?.id),
          ),
        if (done.isNotEmpty) ...[
          const SectionTitle('Concluídos'),
          for (final g in done)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: GroupCard(group: g, userId: user?.id),
            ),
        ],
      ],
    );
  }
}

Future<void> showJoinGroupSheet(BuildContext context, WidgetRef ref) async {
  final code = TextEditingController();
  final router = GoRouter.of(context);
  final groupId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _JoinSheet(controller: code),
  );
  code.dispose();
  if (groupId != null) router.push('/groups/$groupId');
}

class _JoinSheet extends ConsumerStatefulWidget {
  const _JoinSheet({required this.controller});

  final TextEditingController controller;

  @override
  ConsumerState<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends ConsumerState<_JoinSheet> {
  bool _loading = false;

  Future<void> _join() async {
    final code = widget.controller.text.replaceAll(' ', '');
    if (code.length < 6) return;
    setState(() => _loading = true);
    final nav = Navigator.of(context);
    String? id;
    await runGuarded(context, () async {
      final user = ref.read(currentUserProvider)!;
      await ref.read(groupsProvider.notifier).mutate((repo) async {
        id = await repo.joinByCode(code, user.name);
      });
    });
    if (!mounted) return;
    setState(() => _loading = false);
    if (id != null) nav.pop(id);
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
            Text('Entrar num grupo', style: AppTheme.display(context, size: 22)),
            const SizedBox(height: 4),
            Text('Usa o código que te enviaram.', style: TextStyle(color: context.palette.mutedForeground)),
            const SizedBox(height: 16),
            TextField(
              controller: widget.controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: AppTheme.display(context, size: 24).copyWith(letterSpacing: 3),
              onSubmitted: (_) => _join(),
              decoration: const InputDecoration(hintText: 'ABCDE 12345'),
            ),
            const SizedBox(height: 16),
            LoadingButton(label: 'Entrar', loading: _loading, onPressed: _join),
          ],
        ),
      ),
    );
  }
}
