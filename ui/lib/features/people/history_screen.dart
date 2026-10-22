import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../profile/plus.dart';

/// Um ano no histórico de uma pessoa (ver GET /people/:id/history).
class HistoryYear {
  const HistoryYear({required this.year, this.cards = const [], this.gifts = const [], this.groupGifts = const []});

  final int year;
  final List<({String body, DateTime date, bool onWall, String? mediaKind})> cards;
  final List<({String title, double? price, DateTime date})> gifts;
  final List<({String title, double amount, DateTime date})> groupGifts;

  bool get isEmpty => cards.isEmpty && gifts.isEmpty && groupGifts.isEmpty;

  factory HistoryYear.fromJson(Map<String, dynamic> j) {
    DateTime d(Object? v) => DateTime.parse(v as String).toLocal();
    List<Map<String, dynamic>> rows(String k) => [for (final r in (j[k] as List? ?? const [])) (r as Map).cast<String, dynamic>()];
    return HistoryYear(
      year: (j['year'] as num).toInt(),
      cards: [
        for (final r in rows('cards'))
          (body: r['body'] as String? ?? '', date: d(r['created_at']), onWall: r['via'] == 'wall', mediaKind: r['media_kind'] as String?),
      ],
      gifts: [
        for (final r in rows('gifts'))
          (title: r['title'] as String? ?? '', price: (r['price'] as num?)?.toDouble(), date: d(r['purchased_at'])),
      ],
      groupGifts: [
        for (final r in rows('group_gifts'))
          (title: r['title'] as String? ?? '', amount: (r['amount'] as num).toDouble(), date: d(r['purchased_at'])),
      ],
    );
  }
}

typedef PersonHistory = ({List<HistoryYear> years, List<int> lockedYears});

/// O histórico vem do servidor (no plano Grátis só o ano atual). `null` sem servidor.
final personHistoryProvider = FutureProvider.autoDispose.family<PersonHistory?, String>((ref, personId) async {
  final api = ref.watch(apiClientProvider);
  // Volta a pedir quando o plano muda (os anos bloqueados passam a aparecer).
  ref.watch(isPlusProvider);
  if (api == null) return null;
  final res = ((await api.get('/people/$personId/history')) as Map).cast<String, dynamic>();
  return (
    years: [for (final y in res['years'] as List) HistoryYear.fromJson((y as Map).cast<String, dynamic>())],
    lockedYears: [for (final y in res['locked_years'] as List) (y as num).toInt()],
  );
});

/// O que escreveste e deste a uma pessoa, ano a ano.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(dataProvider).person(personId);
    final history = ref.watch(personHistoryProvider(personId));
    return Scaffold(
      appBar: AppBar(title: Text(person == null ? 'Histórico' : 'Histórico de ${person.firstName}')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(personHistoryProvider(personId))),
        data: (h) {
          if (h == null) {
            return const EmptyState(
              icon: LucideIcons.history,
              title: 'Só com conta online',
              message: 'O histórico guarda-se no servidor, com os cartões que enviaste e as prendas que compraste.',
            );
          }
          if (h.years.every((y) => y.isEmpty) && h.lockedYears.isEmpty) {
            return const EmptyState(
              icon: LucideIcons.history,
              title: 'Ainda sem histórico',
              message: 'Os cartões que enviares e as prendas que marcares como compradas ficam aqui, ano a ano.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              for (final y in h.years) _YearSection(year: y),
              if (h.lockedYears.isNotEmpty) _LockedYears(years: h.lockedYears),
            ],
          );
        },
      ),
    );
  }
}

class _YearSection extends StatelessWidget {
  const _YearSection({required this.year});

  final HistoryYear year;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.mutedForeground;
    Widget row(IconData icon, String title, String subtitle) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 18, color: context.colors.primary)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
                Text(subtitle, style: context.text.bodySmall?.copyWith(color: muted)),
              ],
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${year.year}', style: AppTheme.display(context, size: 24)),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in year.cards)
                  row(
                    switch (c.mediaKind) {
                      'image' => LucideIcons.image,
                      'video' => LucideIcons.video,
                      'audio' => LucideIcons.mic,
                      _ => LucideIcons.mailOpen,
                    },
                    c.body,
                    '${c.onWall ? 'No mural' : 'Cartão'} · ${Fmt.dayMonth(c.date)}',
                  ),
                for (final g in year.gifts)
                  row(LucideIcons.gift, g.title, [if (g.price != null) Fmt.money(g.price!), Fmt.dayMonth(g.date)].join(' · ')),
                for (final g in year.groupGifts)
                  row(LucideIcons.usersRound, g.title, 'Prenda em grupo · ${Fmt.money(g.amount)} · ${Fmt.dayMonth(g.date)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Anos que o plano Grátis não mostra.
class _LockedYears extends ConsumerWidget {
  const _LockedYears({required this.years});

  final List<int> years;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fg = context.palette.accentForeground;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AppCard(
        color: context.palette.accent,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PlusBadge(),
            const SizedBox(height: 8),
            Text(
              years.length == 1 ? 'Mais 1 ano de histórico (${years.first})' : 'Mais ${years.length} anos de histórico (${years.join(', ')})',
              style: context.text.titleSmall?.copyWith(color: fg),
            ),
            const SizedBox(height: 4),
            Text(
              'No plano Grátis vês o ano atual. Com o Birthdayly+ vês tudo o que já lhe escreveste e deste.',
              style: context.text.bodySmall?.copyWith(color: fg.withValues(alpha: 0.85)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => requirePlus(context, ref, feature: 'O histórico completo'),
                child: const Text('Ver tudo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
