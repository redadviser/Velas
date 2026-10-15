import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/constants.dart';
import '../../core/i18n/translations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import '../../data/models/group_models.dart';
import '../groups/group_widgets.dart';
import '../groups/invite_widgets.dart';
import 'chat_format.dart';
import 'chat_widgets.dart';

enum ConversationFilter {
  all(Keys.chatFilterAll),
  gifts(Keys.chatFilterGifts),
  direct(Keys.chatFilterDirect),
  unread(Keys.chatFilterUnread);

  const ConversationFilter(this.labelKey);
  final String labelKey;
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
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
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
                      context.trPlural(Keys.chatFriendRequests, requests),
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
                    label: Text(context.tr(f.labelKey)),
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
            title: context.tr(Keys.chatEmptyTitle),
            message: context.tr(chat ? Keys.chatEmptyMessage : Keys.chatEmptyMessageLocal),
            action: Column(
              children: [
                FilledButton.icon(
                  onPressed: () => context.push('/groups/new'),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: Text(context.tr(Keys.chatEmptyCreateGroup)),
                  style: FilledButton.styleFrom(minimumSize: const Size(240, 52)),
                ),
                if (supportsInvites) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => showJoinGroupSheet(context, ref),
                    child: Text(context.tr(Keys.chatEmptyHaveCode)),
                  ),
                ],
                if (chat)
                  TextButton(
                    onPressed: () => context.push('/friends'),
                    child: Text(context.tr(Keys.chatEmptyAddFriends)),
                  ),
              ],
            ),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Text(
              context.tr(switch (_filter) {
                ConversationFilter.unread => Keys.chatFilterEmptyUnread,
                ConversationFilter.direct => Keys.chatFilterEmptyDirect,
                _ => Keys.chatFilterEmptyGifts,
              }),
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

/// Segunda linha de uma conversa: quem está a escrever, se a minha última
/// mensagem já foi vista ("Vista por …"), ou a última mensagem.
class _Preview extends ConsumerWidget {
  const _Preview({
    required this.conversation,
    required this.myId,
    required this.isGroup,
    required this.fallback,
    this.others,
  });

  final Conversation? conversation;
  final String? myId;
  final bool isGroup;

  /// Sem mensagens.
  final String fallback;

  /// Quantas pessoas (além de mim) podem ver ("Vista por todos").
  final int? others;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conversation;
    final muted = context.palette.mutedForeground;
    final unread = (c?.unreadCount ?? 0) > 0;
    final style = context.text.bodyMedium?.copyWith(color: unread ? context.colors.onSurface : muted);
    final typing = c == null ? const <String, String>{} : ref.watch(conversationTypingProvider(c.id));

    Widget line(String text, {IconData? icon, Color? color, bool italic = false}) => Row(
      children: [
        if (icon != null) ...[Icon(icon, size: 15, color: color ?? muted), const SizedBox(width: 4)],
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style?.copyWith(color: color, fontStyle: italic ? FontStyle.italic : null),
          ),
        ),
      ],
    );

    if (typing.isNotEmpty) {
      return line(
        isGroup ? ChatFormat.typing(typing.values) : context.tr(Keys.chatTypingSelf),
        color: context.colors.primary,
        italic: true,
      );
    }
    final last = c?.lastMessage;
    if (last == null) return line(fallback);
    if (last.senderId == myId && !last.deleted) {
      if (c!.seenBy.isNotEmpty) {
        return line(
          ChatFormat.seenBy(c.seenBy, others: others),
          icon: LucideIcons.checkCheck,
          color: context.colors.primary,
        );
      }
      return line(context.tr(Keys.chatPreviewYou, {'text': last.preview}), icon: LucideIcons.check);
    }
    final text = isGroup && last.senderName.isNotEmpty && last.senderId != myId
        ? context.tr(Keys.chatPreviewSender, {'name': last.senderName.split(' ').first, 'text': last.preview})
        : last.preview;
    return line(text, italic: last.deleted);
  }
}

class _TileLayout extends StatelessWidget {
  const _TileLayout({
    required this.avatar,
    required this.title,
    required this.preview,
    required this.onTap,
    this.time,
    this.unread = 0,
    this.footer,
  });

  final Widget avatar;
  final String title;
  final Widget preview;
  final VoidCallback onTap;
  final DateTime? time;
  final int unread;
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
                          ChatFormat.listTime(time!),
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
                      Expanded(child: preview),
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

/// Conversa privada com um amigo (com a bolinha verde se estiver online).
class ConversationTile extends StatelessWidget {
  const ConversationTile({super.key, required this.conversation, required this.myId});

  final Conversation conversation;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    return _TileLayout(
      avatar: ConversationAvatar(conversation: c),
      title: c.title,
      preview: _Preview(conversation: c, myId: myId, isGroup: false, fallback: context.tr(Keys.chatSayHello)),
      time: c.lastMessage?.createdAt,
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
    final next = g.nextBirthday;
    final me = g.memberFor(myId);
    final muted = context.palette.mutedForeground;
    void openGroup() => context.push('/groups/${g.id}');

    final (String label, Color bg, Color fg) status = g.purchasedAt != null
        ? (context.tr(Keys.chatGiftPurchased), context.palette.success.withValues(alpha: 0.14), context.palette.success)
        : me != null && g.isBuyer(me)
        ? (
            g.awaitingConfirmationCount > 0
                ? context.trPlural(Keys.chatGiftAwaiting, g.awaitingConfirmationCount)
                : context.tr(Keys.chatGiftYouBuy),
            context.palette.accent,
            context.palette.accentForeground,
          )
        : me == null
        ? (
            context.tr(Keys.chatGiftCollected, {
              'confirmed': Fmt.money(g.confirmedAmount),
              'target': Fmt.money(g.targetAmount),
            }),
            context.palette.muted,
            muted,
          )
        : switch (g.statusOf(me)) {
            ContributionStatus.pending => (
              context.tr(Keys.chatGiftPay, {'amount': Fmt.money(g.shareOf(me))}),
              context.colors.primary,
              context.colors.onPrimary,
            ),
            ContributionStatus.paid => (
              context.tr(Keys.chatGiftToConfirm),
              statusStyle(context, ContributionStatus.paid).bg,
              statusStyle(context, ContributionStatus.paid).fg,
            ),
            ContributionStatus.confirmed => (
              context.tr(Keys.chatGiftPaid),
              statusStyle(context, ContributionStatus.confirmed).bg,
              statusStyle(context, ContributionStatus.confirmed).fg,
            ),
          };
    // Quem mais pode ver as mensagens do grupo (para "Vista por todos").
    final others = g.members.where((m) => m.userId != null && m.userId != myId).length;

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
      preview: _Preview(
        conversation: c,
        myId: myId,
        isGroup: true,
        others: others,
        fallback: c == null
            ? context.trPlural(Keys.commonPeople, g.members.length)
            : context.tr(Keys.chatGroupTalkHere),
      ),
      time: c?.lastMessage?.createdAt,
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
              next == null
                  ? context.tr(Keys.chatGiftForName, {'name': g.celebrantName})
                  : context.tr(Keys.chatGiftForNameDate, {'name': g.celebrantName, 'date': Fmt.dayMonth(next)}),
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
            child: Text(ctx.tr(Keys.chatNewTitle), style: AppTheme.display(ctx, size: 22)),
          ),
          ListTile(
            leading: const Icon(LucideIcons.gift),
            title: Text(ctx.tr(Keys.chatNewGroup)),
            subtitle: Text(ctx.tr(Keys.chatNewGroupHint)),
            onTap: () => Navigator.pop(ctx, 'group'),
          ),
          if (chat)
            ListTile(
              leading: const Icon(LucideIcons.messageCircle),
              title: Text(ctx.tr(Keys.chatNewDirect)),
              onTap: () => Navigator.pop(ctx, 'direct'),
            ),
          if (supportsInvites)
            ListTile(
              leading: const Icon(LucideIcons.ticket),
              title: Text(ctx.tr(Keys.chatNewCode)),
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
    showMessage(context, context.tr(Keys.chatNewNeedFriend));
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
            child: Text(ctx.tr(Keys.chatNewPickFriend), style: AppTheme.display(ctx, size: 22)),
          ),
          for (final f in friends)
            ListTile(
              leading: PresenceAvatar(user: f),
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
  final ok = await runGuarded(
    context,
    () async => id = await ref.read(conversationsProvider.notifier).openDirect(userId),
  );
  if (ok && id != null) router.push('/chats/$id');
}
