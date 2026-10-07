import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../data/models/group_models.dart';
import '../gifts/gift_widgets.dart';
import '../groups/group_widgets.dart';

class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({super.key, required this.personId});

  final String personId;

  Future<void> _delete(BuildContext context, WidgetRef ref, Person p) async {
    final ok = await confirmDialog(
      context,
      title: 'Eliminar ${p.firstName}?',
      message:
          'Vais perder o aniversário, as ideias de presente e as mensagens guardadas. Esta ação não pode ser desfeita.',
    );
    if (!ok || !context.mounted) return;
    final router = GoRouter.of(context);
    final done = await runGuarded(
      context,
      () => ref.read(dataRepositoryProvider)!.deletePerson(p.id),
      success: '${p.firstName} foi eliminado(a).',
    );
    if (done) router.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataProvider);
    final user = ref.watch(currentUserProvider);
    final person = data.person(personId);

    if (person == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: LucideIcons.userX,
          title: 'Pessoa não encontrada',
          message: 'Pode ter sido eliminada noutro dispositivo.',
        ),
      );
    }

    final category = data.category(person.categoryId);
    final color = personColor(person, data);
    final days = person.daysUntil();
    final next = person.nextBirthday();
    final gifts = data.giftsFor(person.id)..sort((a, b) => a.purchased == b.purchased ? 0 : (a.purchased ? 1 : -1));
    final message = data.messageFor(person.id);
    final groups = (ref.watch(groupsProvider).value ?? const <GiftGroup>[])
        .where((g) => g.personId == person.id)
        .toList();
    final reminders = person.reminderDays ?? user?.defaultReminderDays ?? kDefaultReminderDays;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(LucideIcons.pencil, size: 20),
            onPressed: () => context.push('/person/${person.id}/edit'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.ellipsisVertical, size: 20),
            onSelected: (v) {
              if (v == 'delete') _delete(context, ref, person);
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(LucideIcons.trash2, size: 18, color: ctx.colors.error),
                    const SizedBox(width: 12),
                    Text('Eliminar', style: TextStyle(color: ctx.colors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Center(
            child: PersonAvatar(person: person, color: color, size: 96, celebrate: days == 0),
          ),
          const SizedBox(height: 14),
          Text(person.name, textAlign: TextAlign.center, style: AppTheme.display(context, size: 28)),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: [
              if (person.relation.isNotEmpty) Pill(label: person.relation),
              if (category != null)
                Pill(
                  label: category.name,
                  background: swatch(category.color).withValues(alpha: 0.14),
                  foreground: Color.lerp(swatch(category.color), context.colors.onSurface, 0.35),
                ),
            ],
          ),
          const SizedBox(height: 20),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _Stat(value: person.turningAge?.toString() ?? '—', label: days == 0 ? 'anos hoje' : 'vai fazer'),
                  const VerticalDivider(),
                  _Stat(
                    value: '${next.day} ${Fmt.monthShort(next.month).toLowerCase()}',
                    label: Fmt.weekday(next).toLowerCase(),
                  ),
                  const VerticalDivider(),
                  _Stat(
                    value: days == 0 ? '🎉' : '$days',
                    label: days == 0 ? 'é hoje!' : (days == 1 ? 'dia' : 'dias'),
                    highlight: days <= 7,
                  ),
                ],
              ),
            ),
          ),
          if (person.year != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Nasceu a ${Fmt.birthDate(person.day, person.month, person.year)}',
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
              ),
            ),
          const SizedBox(height: 12),
          AppCard(
            onTap: () => context.push('/person/${person.id}/edit'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(LucideIcons.bellRing, size: 18, color: context.colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lembretes', style: context.text.titleSmall),
                      Text(
                        '${reminders.map(reminderLabel).join(', ')}${person.reminderDays == null ? ' · predefinição' : ''}',
                        style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 18, color: context.palette.mutedForeground),
              ],
            ),
          ),
          SectionTitle('Mensagem', padding: const EdgeInsets.fromLTRB(4, 28, 0, 10)),
          if (message == null)
            AppCard(
              onTap: () => context.push('/person/${person.id}/message'),
              color: context.palette.accent,
              child: Row(
                children: [
                  Icon(LucideIcons.sparkles, color: context.palette.accentForeground),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Prepara já os parabéns',
                          style: context.text.titleSmall?.copyWith(color: context.palette.accentForeground),
                        ),
                        Text(
                          'Escreve a tua ou parte de uma sugestão.',
                          style: context.text.bodySmall?.copyWith(
                            color: context.palette.accentForeground.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.arrowRight, size: 18, color: context.palette.accentForeground),
                ],
              ),
            )
          else
            _MessageCard(message: message, personId: person.id),
          SectionTitle(
            'Presentes',
            action: 'Adicionar',
            onAction: () => showGiftEditor(context, ref, personId: person.id),
            padding: const EdgeInsets.fromLTRB(4, 28, 0, 6),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (person.giftBudget != null || gifts.any((g) => g.price != null))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: BudgetBar(budget: person.giftBudget, gifts: gifts),
                  ),
                if (gifts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Sem ideias ainda. Guarda aqui o que te vier à cabeça ao longo do ano.',
                      style: TextStyle(color: context.palette.mutedForeground),
                    ),
                  )
                else ...[
                  if (person.giftBudget != null || gifts.any((g) => g.price != null)) const Divider(),
                  for (final g in gifts) GiftRow(gift: g, padding: const EdgeInsets.only(left: 4, right: 8)),
                ],
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => showGiftEditor(context, ref, personId: person.id),
                        icon: const Icon(LucideIcons.plus, size: 18),
                        label: const Text('Nova ideia'),
                        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                    Container(width: 1, height: 24, color: context.palette.border),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => context.push('/groups/new?personId=${person.id}'),
                        icon: const Icon(LucideIcons.usersRound, size: 18),
                        label: const Text('Em grupo'),
                        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          for (final g in groups) ...[const SizedBox(height: 12), GroupCard(group: g, userId: user?.id)],
          if (person.notes.isNotEmpty) ...[
            SectionTitle('Notas', padding: const EdgeInsets.fromLTRB(4, 28, 0, 10)),
            AppCard(child: Text(person.notes, style: context.text.bodyMedium)),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.highlight = false});

  final String value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(value, style: AppTheme.display(context, size: 24, color: highlight ? context.colors.primary : null)),
        const SizedBox(height: 2),
        Text(label, style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground, fontSize: 12)),
      ],
    ),
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.personId});

  final BirthdayMessage message;
  final String personId;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => context.push('/person/$personId/message'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 3,
                    height: 40,
                    color: context.colors.primary,
                    margin: const EdgeInsets.only(right: 12, top: 2),
                  ),
                  Expanded(
                    child: Text(
                      message.body,
                      style: AppTheme.display(context, size: 16).copyWith(fontWeight: FontWeight.w400, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: message.body));
                    if (context.mounted) showMessage(context, 'Mensagem copiada.');
                  },
                  icon: const Icon(LucideIcons.copy, size: 16),
                  label: const Text('Copiar'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => SharePlus.instance.share(ShareParams(text: message.body)),
                  icon: const Icon(LucideIcons.send, size: 16),
                  label: const Text('Enviar'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => context.push('/person/$personId/message'),
                  icon: const Icon(LucideIcons.pencil, size: 16),
                  label: const Text('Editar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
