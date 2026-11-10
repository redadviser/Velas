import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/models/party_models.dart';

/// "Sábado, 24 de maio · 19:30" (ou "Data por marcar").
String partyWhen(Party p) {
  final d = p.startsAt;
  if (d == null) return 'Data por marcar';
  final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  return '${Fmt.weekdayDayMonth(d)} · $time';
}

/// Cartão de uma festa nas listas (Início e Festas).
class PartyCard extends StatelessWidget {
  const PartyCard({super.key, required this.party, this.width});

  final Party party;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final p = party;
    final going = p.count(Rsvp.yes);
    return SizedBox(
      width: width,
      child: AppCard(
        color: context.palette.violetSoft,
        onTap: () => context.push('/parties/${p.id}'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.sparkles, size: 14, color: context.colors.secondary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'SURPRESA PARA ${p.celebrantName.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.eyebrow(context, color: context.colors.secondary).copyWith(fontSize: 10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTheme.display(context, size: 16)),
            const SizedBox(height: 4),
            Text(
              partyWhen(p),
              maxLines: 2,
              style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                Text(
                  going == 1 ? '1 vai' : '$going vão',
                  style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground),
                ),
                if (p.tasks.isNotEmpty)
                  Text(
                    '${p.doneTasks} de ${p.tasks.length} tarefas',
                    style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pede o código e entra na festa.
Future<void> joinPartyWithCode(BuildContext context, WidgetRef ref) async {
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final c = TextEditingController();
      return AlertDialog(
        title: Text('Entrar numa festa', style: AppTheme.display(ctx, size: 22)),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'Código que te enviaram'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            child: const Text('Entrar'),
          ),
        ],
      );
    },
  );
  if (code == null || code.trim().isEmpty || !context.mounted) return;
  Party? joined;
  final ok = await runGuarded(context, () async {
    joined = await ref.read(partiesProvider.notifier).run((repo) => repo.join(code.trim()));
  });
  if (ok && joined != null && context.mounted) context.push('/parties/${joined!.id}');
}

/// Cores de cada resposta (fundo, letra).
(Color, Color) rsvpColors(BuildContext context, Rsvp r) => switch (r) {
  Rsvp.yes => (context.palette.success.withValues(alpha: 0.14), context.palette.success),
  Rsvp.maybe => (AppColors.amber.withValues(alpha: 0.18), Color.lerp(AppColors.amber, context.colors.onSurface, 0.45)!),
  Rsvp.no => (context.colors.error.withValues(alpha: 0.12), context.colors.error),
  Rsvp.pending => (context.palette.muted, context.palette.mutedForeground),
};
