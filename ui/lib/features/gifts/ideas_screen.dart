import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import 'gift_suggestions.dart';
import 'gift_widgets.dart';
import 'wishlist_widgets.dart';
import '../../core/wishlist_providers.dart';
import '../people/linked_friend.dart';
import '../../core/i18n/translations.dart';

class IdeasScreen extends ConsumerStatefulWidget {
  const IdeasScreen({super.key, required this.personId});

  final String personId;

  @override
  ConsumerState<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends ConsumerState<IdeasScreen> {
  GiftTopic? _topic;
  bool _withinBudget = true;
  bool _onlyLiked = true;

  Future<void> _save(Person person, GiftSuggestion s) => runGuarded(
    context,
    () => ref
        .read(dataRepositoryProvider)!
        .saveGift(
          GiftIdea(
            id: const Uuid().v4(),
            personId: person.id,
            title: s.title,
            notes: '${s.description} (${s.range})',
            createdAt: DateTime.now(),
          ),
        ),
    success: tr('Guardada nas ideias para {name}.', {'name': person.firstName}),
  );

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final person = data.person(widget.personId);
    if (person == null) return Scaffold(appBar: AppBar(), body: const SizedBox());
    final saved = data.giftsFor(person.id).where((g) => !g.purchased).toList();
    final savedTitles = {for (final g in data.giftsFor(person.id)) g.title.toLowerCase()};
    final budget = person.giftBudget;
    final friendId = linkedFriend(ref, person.linkedUserId)?.userId;
    final theirs = friendId == null ? null : ref.watch(friendWishlistProvider(friendId)).value;
    final interests = theirs?.interests ?? const <String>[];
    final hasLikes = topicsFor(person, interests: interests).isNotEmpty;
    final list = suggestionsFor(
      person,
      topic: _topic,
      maxPrice: _withinBudget ? budget : null,
      interests: interests,
      onlyLiked: _onlyLiked,
    );
    final muted = context.palette.mutedForeground;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Ideias para {name}', {'name': person.firstName}))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          if (saved.isNotEmpty) ...[
            _Featured(gift: saved.first, person: person),
            if (saved.length > 1) ...[
              const SizedBox(height: 8),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final g in saved.skip(1)) GiftRow(gift: g, padding: const EdgeInsets.only(left: 4, right: 8)),
                  ],
                ),
              ),
            ],
          ],
          if (theirs != null && theirs.items.isNotEmpty) ...[
            SectionTitle(
              context.tr('Pedido por {name}', {'name': person.firstName}),
              padding: const EdgeInsets.fromLTRB(4, 24, 0, 8),
            ),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, w) in theirs.items.indexed) ...[
                    if (i > 0) const Divider(indent: 16, endIndent: 16),
                    WishRow(
                      item: w,
                      trailing: KeepWishButton(person: person, wish: w),
                    ),
                  ],
                ],
              ),
            ),
          ],
          SectionTitle(context.tr('Sugestões'), padding: const EdgeInsets.fromLTRB(4, 24, 0, 8)),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                if (hasLikes) ...[
                  FilterChip(
                    label: Text(context.tr('Gostos de {name}', {'name': person.firstName})),
                    selected: _onlyLiked,
                    onSelected: (v) => setState(() => _onlyLiked = v),
                  ),
                  const SizedBox(width: 8),
                ],
                if (budget != null) ...[
                  FilterChip(
                    label: Text(context.tr('Até {amount}', {'amount': Fmt.money(budget)})),
                    selected: _withinBudget,
                    onSelected: (v) => setState(() => _withinBudget = v),
                  ),
                  const SizedBox(width: 8),
                ],
                for (final t in GiftTopic.values) ...[
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _topic == t,
                    onSelected: (v) => setState(() => _topic = v ? t : null),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                context.tr('Nada com estes filtros. Experimenta tirar algum.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
            ),
          for (final s in list) ...[
            _SuggestionCard(
              suggestion: s,
              saved: savedTitles.contains(s.title.toLowerCase()),
              onSave: () => _save(person, s),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
          Text(
            hasLikes
                ? context.tr('Primeiro aparecem as que combinam com os gostos de {name}.', {'name': person.firstName})
                : context.tr('Escolhe os gostos de {name} (em Editar) e as sugestões passam a ter isso em conta.', {
                    'name': person.firstName,
                  }),
            style: context.text.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

class _Featured extends StatelessWidget {
  const _Featured({required this.gift, required this.person});

  final GiftIdea gift;
  final Person person;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: context.palette.softGradient,
      borderRadius: BorderRadius.circular(AppTheme.radius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Pill(label: context.tr('NAS TUAS IDEIAS'), icon: LucideIcons.heart, dense: true),
        const SizedBox(height: 10),
        Text(gift.title, style: AppTheme.display(context, size: 20)),
        if (gift.notes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(gift.notes, style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground)),
        ],
        if (gift.price != null) ...[
          const SizedBox(height: 6),
          Text(Fmt.money(gift.price!), style: context.text.titleSmall),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => context.push('/groups/new?personId=${person.id}'),
          icon: const Icon(LucideIcons.usersRound, size: 18),
          label: Text(context.tr('Criar grupo com esta ideia')),
        ),
      ],
    ),
  );
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion, required this.saved, required this.onSave});

  final GiftSuggestion suggestion;
  final bool saved;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final tone = AppColors.tones[suggestion.topic.index % AppColors.tones.length];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
      child: Row(
        children: [
          IconBadge(
            icon: suggestion.icon,
            background: isDark ? context.palette.muted : tone.$1,
            foreground: isDark ? context.palette.accentForeground : tone.$2,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(suggestion.title, style: context.text.titleSmall),
                Text(
                  suggestion.description,
                  style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                ),
                Text(suggestion.range, style: context.text.labelMedium),
              ],
            ),
          ),
          saved
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    LucideIcons.check,
                    color: context.palette.accentForeground,
                    semanticLabel: context.tr('Guardada'),
                  ),
                )
              : IconButton(
                  tooltip: context.tr('Guardar ideia'),
                  onPressed: onSave,
                  icon: Icon(LucideIcons.bookmarkPlus, color: context.colors.primary),
                ),
        ],
      ),
    );
  }
}
