import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/models/party_models.dart';
import '../../core/i18n/translations.dart';

/// "Sábado, 24 de maio · 19:30" (ou "Data por marcar").
String partyWhen(Party p) {
  final d = p.startsAt;
  if (d == null) return tr('Data por marcar');
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
                Icon(LucideIcons.cake, size: 14, color: context.colors.secondary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    context.tr('Surpresa para {name}', {'name': p.celebrantName}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelMedium?.copyWith(
                      color: context.colors.secondary,
                      fontWeight: FontWeight.w700,
                    ),
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
                  going == 1 ? context.tr('1 vai') : context.tr('{count} vão', {'count': going}),
                  style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground),
                ),
                if (p.tasks.isNotEmpty)
                  Text(
                    context.tr('{done} de {total} tarefas', {'done': p.doneTasks, 'total': p.tasks.length}),
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

/// Cores de cada resposta (fundo, letra).
(Color, Color) rsvpColors(BuildContext context, Rsvp r) => switch (r) {
  Rsvp.yes => (context.palette.success.withValues(alpha: 0.14), context.palette.success),
  Rsvp.maybe => (AppColors.amber.withValues(alpha: 0.18), Color.lerp(AppColors.amber, context.colors.onSurface, 0.45)!),
  Rsvp.no => (context.colors.error.withValues(alpha: 0.12), context.colors.error),
  Rsvp.pending => (context.palette.muted, context.palette.mutedForeground),
};
