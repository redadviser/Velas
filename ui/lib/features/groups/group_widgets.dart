import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/utils/errors.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../data/api/api_client.dart';
import '../../data/models/group_models.dart';
import '../auth/auth_widgets.dart';
import '../chat/chat_widgets.dart';
import 'invite_links.dart';
import '../../core/utils/text.dart';
import '../../core/i18n/translations.dart';

/// Mensagem para lembrar quem ainda não pagou.
String reminderText(GiftGroup g, List<GroupMember> pending) {
  final buyer = g.buyer?.name ?? tr('quem compra');
  final lines = [for (final m in pending) '• ${m.name}: ${Fmt.money(g.shareOf(m))}'];
  return [
    tr('Olá! 🎁 Falta pouco para a prenda "{title}".', {'title': g.title}),
    if (pending.length == 1)
      tr('A tua parte é {amount}.', {'amount': Fmt.money(g.shareOf(pending.first))})
    else ...[
      tr('Ainda falta:'),
      ...lines,
    ],
    if (g.deadline == null)
      tr('O pagamento é para {buyer}. Obrigado!', {'buyer': buyer})
    else
      tr('O pagamento é para {buyer} até {date}. Obrigado!', {'buyer': buyer, 'date': Fmt.dayMonth(g.deadline!)}),
  ].join('\n');
}

({String label, Color bg, Color fg}) statusStyle(BuildContext context, ContributionStatus s, {bool isBuyer = false}) {
  if (isBuyer) return (label: context.tr('Compra'), bg: context.palette.accent, fg: context.palette.accentForeground);
  return switch (s) {
    ContributionStatus.pending => (
      label: context.tr('Por pagar'),
      bg: context.palette.muted,
      fg: context.palette.mutedForeground,
    ),
    ContributionStatus.paid => (
      label: context.tr('Por confirmar'),
      bg: AppColors.amber.withValues(alpha: 0.16),
      fg: Color.lerp(AppColors.amber, context.colors.onSurface, 0.35)!,
    ),
    ContributionStatus.confirmed => (
      label: context.tr('Pago'),
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
      if (isMe) context.tr('Tu'),
      if (member.userId == group.createdBy) context.tr('Administrador'),
      if (!member.hasAccount) context.tr('Sem conta'),
      if (member.paidMethod != null && !isBuyer) member.paidMethod!.label,
    ];
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (member.photoUrl != null)
              ClipOval(
                child: SizedBox.square(dimension: 36, child: ChatImage(url: member.photoUrl)),
              )
            else
              CircleAvatar(
                radius: 18,
                backgroundColor: swatch(index).withValues(alpha: 0.16),
                child: Text(
                  initialOf(member.name),
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
        ? (context.tr('Prenda comprada'), context.palette.success.withValues(alpha: 0.14), context.palette.success)
        : iAmBuyer
        ? (
            g.awaitingConfirmationCount > 0
                ? context.tr('{count} por confirmar', {'count': g.awaitingConfirmationCount})
                : context.tr('Tu compras'),
            context.palette.accent,
            context.palette.accentForeground,
          )
        : me == null
        ? ('', Colors.transparent, Colors.transparent)
        : switch (g.statusOf(me)) {
            ContributionStatus.pending => (
              context.tr('Pagar {amount}', {'amount': Fmt.money(g.shareOf(me))}),
              context.colors.primary,
              context.colors.onPrimary,
            ),
            ContributionStatus.paid => (
              context.tr('A confirmar'),
              AppColors.amber.withValues(alpha: 0.16),
              Color.lerp(AppColors.amber, context.colors.onSurface, 0.35)!,
            ),
            ContributionStatus.confirmed => (
              context.tr('Pago'),
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
              IconBadge(
                icon: g.purchasedAt != null ? LucideIcons.packageCheck : LucideIcons.gift,
                size: 48,
                background: Theme.of(context).brightness == Brightness.dark
                    ? context.palette.muted
                    : const Color(0xFFF4EADC),
                foreground: Theme.of(context).brightness == Brightness.dark
                    ? context.colors.onSurface
                    : const Color(0xFF7A570C),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.title, style: AppTheme.display(context, size: 19)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (next != null) '${g.celebrantName} · ${Fmt.dayMonth(next)}' else g.celebrantName,
                        context.tr('{count} pessoas', {'count': g.members.length}),
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
          SoftProgress(value: ratio, semanticsLabel: context.tr('Valor recebido')),
          const SizedBox(height: 6),
          Text(
            [
              context.tr('{confirmed} de {target}', {
                'confirmed': Fmt.money(g.confirmedAmount),
                'target': Fmt.money(g.targetAmount),
              }),
              if (g.purchasedAt == null && g.pendingCount > 0)
                g.pendingCount == 1
                    ? context.tr('falta 1 pagamento')
                    : context.tr('faltam {count} pagamentos', {'count': g.pendingCount}),
            ].join(' · '),
            style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// Entrar com um código ou link de convite, de uma prenda em grupo ou de uma
/// festa surpresa: tenta primeiro como grupo e, se não for, como festa.
Future<void> showJoinCodeSheet(BuildContext context, WidgetRef ref) async {
  final router = GoRouter.of(context);
  final route = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _JoinSheet(),
  );
  if (route != null) router.push(route);
}

class _JoinSheet extends ConsumerStatefulWidget {
  const _JoinSheet();

  @override
  ConsumerState<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends ConsumerState<_JoinSheet> {
  // É da folha: só é apagado quando ela sai do ecrã (depois da animação de
  // fechar). Apagá-lo assim que a folha devolvia o resultado rebentava o ecrã.
  final _code = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<String?> _joinGroup(String code) async {
    String? id;
    try {
      final user = ref.read(currentUserProvider)!;
      await ref.read(groupsProvider.notifier).mutate((repo) async {
        id = await repo.joinByCode(code, user.name);
      });
    } on AppException catch (e) {
      if (!identical(e, invalidInviteCode)) rethrow;
    }
    return id == null ? null : '/groups/$id';
  }

  Future<String> _joinParty(String code) async {
    try {
      final party = await ref.read(partiesProvider.notifier).run((repo) => repo.join(code));
      return '/parties/${party!.id}';
    } on ApiException catch (e) {
      if (e.status == 404) throw invalidInviteCode;
      rethrow;
    }
  }

  Future<void> _join() async {
    final text = _code.text.trim();
    final uri = Uri.tryParse(text);
    final partyLink = uri != null && uri.hasScheme ? InviteLinks.partyCodeFrom(uri) : null;
    final code = partyLink?.toUpperCase() ?? InviteLinks.normalizeCode(text);
    if (code.length < 4) return;
    setState(() => _loading = true);
    final nav = Navigator.of(context);
    String? route;
    await runGuarded(context, () async {
      route = (partyLink == null ? await _joinGroup(code) : null) ?? await _joinParty(code);
    });
    if (!mounted) return;
    setState(() => _loading = false);
    if (route != null) nav.pop(route);
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
            Text(context.tr('Tenho um código'), style: AppTheme.display(context, size: 22)),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'Serve para prendas em grupo e festas surpresa. Escreve o código que te enviaram ou cola o link.',
              ),
              style: TextStyle(color: context.palette.mutedForeground),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: AppTheme.display(context, size: 24).copyWith(letterSpacing: 3),
              onSubmitted: (_) => _join(),
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'K7P2 QX9M'),
            ),
            const SizedBox(height: 16),
            LoadingButton(label: context.tr('Entrar'), loading: _loading, onPressed: _join),
          ],
        ),
      ),
    );
  }
}
