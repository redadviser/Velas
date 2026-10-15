import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import '../../data/models/group_models.dart';
import '../groups/group_widgets.dart';
import '../groups/invite_widgets.dart';
import 'chat_widgets.dart';

enum ConversationFilter {
  all('Tudo'),
  gifts('Prendas'),
  direct('Privadas'),
  unread('Não lidas');

  const ConversationFilter(this.label);
  final String label;
}

/// Uma linha da lista: uma prenda em grupo (com a sua conversa) ou uma conversa privada.
sealed class ConversationItem {
  const ConversationItem();

  DateTime get sortKey;
  int get unread;
}

class GroupItem extends ConversationItem {
  const GroupItem(this.group, this.conversation);

  final GiftGroup group;

  /// `null` no modo local, ou enquanto as conversas carregam.
  final Conversation? conversation;

  @override
  DateTime get sortKey => conversation?.lastMessageAt ?? group.createdAt;

  @override
  int get unread => conversation?.unreadCount ?? 0;
}

class DirectItem extends ConversationItem {
  const DirectItem(this.conversation);

  final Conversation conversation;

  @override
  DateTime get sortKey => conversation.sortKey;

  @override
  int get unread => conversation.unreadCount;
}

/// Junta as prendas em grupo e as conversas privadas, mais recentes primeiro.
List<ConversationItem> conversationItems(
  List<GiftGroup> groups,
  List<Conversation> conversations,
  ConversationFilter filter,
) {
  final byId = {for (final c in conversations) c.id: c};
  final items = <ConversationItem>[
    if (filter != ConversationFilter.direct)
      for (final g in groups) GroupItem(g, g.conversationId == null ? null : byId[g.conversationId]),
    if (filter != ConversationFilter.gifts)
      for (final c in conversations)
        if (!c.isGroup) DirectItem(c),
  ];
  return [
    for (final i in items)
      if (filter != ConversationFilter.unread || i.unread > 0) i,
  ]..sort((a, b) => b.sortKey.compareTo(a.sortKey));
}

/// Coisas à espera de mim: mensagens por ler, pedidos de amizade e prendas por pagar.
final conversationsBadgeProvider = Provider<int>((ref) {
  final user = ref.watch(currentUserProvider);
  final toPay = (ref.watch(groupsProvider).value ?? const <GiftGroup>[]).where((g) {
    final me = g.memberFor(user?.id);
    return g.purchasedAt == null && me != null && g.statusOf(me) == ContributionStatus.pending;
  }).length;
  final int unread = ref.watch(unreadTotalProvider);
  final int requests = ref.watch(incomingFriendRequestsProvider);
  return toPay + unread + requests;
});

/// Separador "Conversas" dos Presentes: prendas em grupo e conversas privadas
/// numa só lista, com filtros (como no WhatsApp).
class ConversationsList extends ConsumerStatefulWidget {
  const ConversationsList({super.key});

  @override
  ConsumerState<ConversationsList> createState() => _ConversationsListState();
}

class _ConversationsListState extends ConsumerState<ConversationsList> {
  var _filter = ConversationFilter.all;

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatRepositoryProvider) != null;
    final groupsAsync = ref.watch(groupsProvider);
    final conversationsAsync = ref.watch(conversationsProvider);
    final user = ref.watch(currentUserProvider);
    final requests = ref.watch(incomingFriendRequestsProvider);
    final supportsInvites = ref.watch(groupRepositoryProvider)?.supportsInvites ?? false;

    if (groupsAsync.hasError && !groupsAsync.hasValue) {
      return ErrorRetry(error: groupsAsync.error!, onRetry: () => ref.invalidate(groupsProvider));
    }
    final groups = groupsAsync.value;
    if (groups == null) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)));
    }
    final conversations = conversationsAsync.value ?? const <Conversation>[];
    final items = conversationItems(groups, conversations, chat ? _filter : ConversationFilter.gifts);
    final nothingAtAll = groups.isEmpty && !conversations.any((c) => !c.isGroup);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InvitationsInbox(onAccepted: (id) => context.push('/groups/$id')),
        if (requests > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: AppCard(
              color: context.palette.accent,
              onTap: () => context.push('/friends'),
              child: Row(
                children: [
                  Icon(LucideIcons.userPlus, color: context.palette.accentForeground),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      requests == 1 ? '1 pedido de amizade' : '$requests pedidos de amizade',
                      style: context.text.titleSmall?.copyWith(color: context.palette.accentForeground),
                    ),
                  ),
                  Icon(LucideIcons.chevronRight, size: 18, color: context.palette.accentForeground),
                ],
              ),
            ),
          ),
        if (chat && !nothingAtAll)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(
              children: [
                for (final f in ConversationFilter.values) ...[
                  ChoiceChip(
                    label: Text(f.label),
                    selected: _filter == f,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        if (nothingAtAll)
          EmptyState(
            icon: LucideIcons.messagesSquare,
            title: 'Prendas em grupo e conversas',
            message: chat
                ? 'Junta amigos ou família para uma prenda: combinam tudo na conversa do grupo e pagam diretamente a quem compra. Também podes falar em privado com os teus amigos.'
                : 'Junta amigos ou família, combinem o valor de cada um e paguem diretamente a quem compra — por MB WAY, transferência ou em mão.',
            action: Column(
              children: [
                FilledButton.icon(
                  onPressed: () => context.push('/groups/new'),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: const Text('Criar prenda em grupo'),
                  style: FilledButton.styleFrom(minimumSize: const Size(240, 52)),
                ),
                if (supportsInvites) ...[
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => showJoinGroupSheet(context, ref), child: const Text('Tenho um código')),
                ],
                if (chat)
                  TextButton(onPressed: () => context.push('/friends'), child: const Text('Adicionar amigos')),
              ],
            ),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Text(
              switch (_filter) {
                ConversationFilter.unread => 'Está tudo lido. 👌',
                ConversationFilter.direct => 'Ainda sem conversas privadas. Toca em "Nova" para falar com um amigo.',
                _ => 'Ainda sem prendas em grupo.',
              },
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.mutedForeground),
            ),
          )
        else ...[
          const SizedBox(height: 4),
          for (final item in items)
            switch (item) {
              GroupItem(:final group, :final conversation) => GroupConversationTile(
                group: group,
                conversation: conversation,
                myId: user?.id,
              ),
              DirectItem(:final conversation) => ConversationTile(conversation: conversation, myId: user?.id),
            },
        ],
      ],
    );
  }
}

/// "Tu: …", "Gil: …" antes da última mensagem.
String _preview(LastMessage last, String? myId, {required bool isGroup}) {
  final who = last.senderId == myId
      ? 'Tu: '
      : isGroup && last.senderName.isNotEmpty
      ? '${last.senderName.split(' ').first}: '
      : '';
  return '$who${last.preview}';
}

class _TileLayout extends StatelessWidget {
  const _TileLayout({
    required this.avatar,
    required this.title,
    required this.preview,
    required this.onTap,
    this.time,
    this.unread = 0,
    this.italic = false,
    this.footer,
  });

  final Widget avatar;
  final String title;
  final String preview;
  final VoidCallback onTap;
  final DateTime? time;
  final int unread;
  final bool italic;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.mutedForeground;
    final hasUnread = unread > 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall?.copyWith(fontWeight: hasUnread ? FontWeight.w800 : null),
                        ),
                      ),
                      if (time != null)
                        Text(
                          Fmt.chatTime(time!),
                          style: context.text.labelSmall?.copyWith(
                            color: hasUnread ? context.colors.primary : muted,
                            fontWeight: hasUnread ? FontWeight.w700 : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(
                            color: hasUnread ? context.colors.onSurface : muted,
                            fontStyle: italic ? FontStyle.italic : null,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[const SizedBox(width: 8), CountBadge(count: unread)],
                    ],
                  ),
                  if (footer != null) ...[const SizedBox(height: 6), footer!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Conversa privada com um amigo.
class ConversationTile extends StatelessWidget {
  const ConversationTile({super.key, required this.conversation, required this.myId});

  final Conversation conversation;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final last = c.lastMessage;
    return _TileLayout(
      avatar: ConversationAvatar(conversation: c),
      title: c.title,
      preview: last == null ? 'Diz olá 👋' : _preview(last, myId, isGroup: c.isGroup),
      italic: last?.deleted ?? false,
      time: last?.createdAt,
      unread: c.unreadCount,
      onTap: () => context.push('/chats/${c.id}'),
    );
  }
}

/// Prenda em grupo: a conversa do grupo e, por baixo, o estado do pagamento.
/// Tocar abre a conversa; tocar no estado abre a prenda.
class GroupConversationTile extends StatelessWidget {
  const GroupConversationTile({super.key, required this.group, required this.conversation, required this.myId});

  final GiftGroup group;
  final Conversation? conversation;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final c = conversation;
    final last = c?.lastMessage;
    final next = g.nextBirthday;
    final me = g.memberFor(myId);
    final muted = context.palette.mutedForeground;
    void openGroup() => context.push('/groups/${g.id}');

    final (String label, Color bg, Color fg) status = g.purchasedAt != null
        ? ('Comprada', context.palette.success.withValues(alpha: 0.14), context.palette.success)
        : me != null && g.isBuyer(me)
        ? (
            g.awaitingConfirmationCount > 0 ? '${g.awaitingConfirmationCount} por confirmar' : 'Tu compras',
            context.palette.accent,
            context.palette.accentForeground,
          )
        : me == null
        ? ('${Fmt.money(g.confirmedAmount)} de ${Fmt.money(g.targetAmount)}', context.palette.muted, muted)
        : switch (g.statusOf(me)) {
            ContributionStatus.pending => ('Pagar ${Fmt.money(g.shareOf(me))}', context.colors.primary, context.colors.onPrimary),
            final s => (statusStyle(context, s).label, statusStyle(context, s).bg, statusStyle(context, s).fg),
          };

    return _TileLayout(
      avatar: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: g.purchasedAt == null ? AppColors.brandGradient : null,
          color: g.purchasedAt == null ? null : context.palette.muted,
          shape: BoxShape.circle,
        ),
        child: Icon(LucideIcons.gift, color: g.purchasedAt == null ? Colors.white : muted, size: 22),
      ),
      title: g.title,
      preview: last == null
          ? (c == null ? '${g.members.length} pessoas' : 'Combinem aqui a prenda 💬')
          : _preview(last, myId, isGroup: true),
      italic: last?.deleted ?? false,
      time: last?.createdAt,
      unread: c?.unreadCount ?? 0,
      // Sem conversa (modo local) abre logo a prenda.
      onTap: c == null ? openGroup : () => context.push('/chats/${c.id}'),
      footer: Row(
        children: [
          GestureDetector(
            onTap: openGroup,
            child: Pill(label: status.$1, background: status.$2, foreground: status.$3, dense: true),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              next == null ? 'Para ${g.celebrantName}' : 'Para ${g.celebrantName} · ${Fmt.dayMonth(next)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Nova": prenda em grupo, conversa com um amigo ou entrar com código.
Future<void> showNewConversationSheet(BuildContext context, WidgetRef ref) async {
  final chat = ref.read(chatRepositoryProvider) != null;
  final supportsInvites = ref.read(groupRepositoryProvider)?.supportsInvites ?? false;
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Nova', style: AppTheme.display(ctx, size: 22)),
          ),
          ListTile(
            leading: const Icon(LucideIcons.gift),
            title: const Text('Prenda em grupo'),
            subtitle: const Text('Juntar pessoas para uma prenda, com conversa'),
            onTap: () => Navigator.pop(ctx, 'group'),
          ),
          if (chat)
            ListTile(
              leading: const Icon(LucideIcons.messageCircle),
              title: const Text('Conversa com um amigo'),
              onTap: () => Navigator.pop(ctx, 'direct'),
            ),
          if (supportsInvites)
            ListTile(
              leading: const Icon(LucideIcons.ticket),
              title: const Text('Entrar com código'),
              onTap: () => Navigator.pop(ctx, 'code'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'group':
      context.push('/groups/new');
    case 'direct':
      await startDirectChat(context, ref);
    case 'code':
      await showJoinGroupSheet(context, ref);
  }
}

/// Escolher um amigo e abrir a conversa privada com ele.
Future<void> startDirectChat(BuildContext context, WidgetRef ref) async {
  final friends = ref.read(friendsProvider).value?.friends ?? const [];
  if (friends.isEmpty) {
    showMessage(context, 'Adiciona primeiro um amigo para conversarem em privado.');
    context.push('/friends');
    return;
  }
  final friend = await showModalBottomSheet<ChatUser>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Conversar com…', style: AppTheme.display(ctx, size: 22)),
          ),
          for (final f in friends)
            ListTile(
              leading: UserAvatar(user: f),
              title: Text(f.name),
              subtitle: f.username.isEmpty ? null : Text('@${f.username}'),
              onTap: () => Navigator.pop(ctx, f),
            ),
        ],
      ),
    ),
  );
  if (friend == null || !context.mounted) return;
  await openDirectChat(context, ref, friend.userId);
}

Future<void> openDirectChat(BuildContext context, WidgetRef ref, String userId) async {
  final router = GoRouter.of(context);
  String? id;
  final ok = await runGuarded(context, () async => id = await ref.read(conversationsProvider.notifier).openDirect(userId));
  if (ok && id != null) router.push('/chats/$id');
}
