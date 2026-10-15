import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/constants.dart';
import '../../core/i18n/translations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import '../chat/chat_format.dart';
import '../chat/chat_widgets.dart';

/// No Início, como uma caixa de correio: as conversas com mensagens por ler
/// (as silenciadas não entram) e os pedidos de amizade. Só aparece se houver
/// alguma coisa à espera.
class HomeInbox extends ConsumerWidget {
  const HomeInbox({super.key});

  static const _maxRows = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(chatRepositoryProvider) == null) return const SizedBox.shrink();
    final me = ref.watch(currentUserProvider)?.id;
    final unread =
        (ref.watch(conversationsProvider).value ?? const <Conversation>[])
            .where((c) => c.unreadCount > 0 && !c.isMuted)
            .toList()
          ..sort((a, b) => b.sortKey.compareTo(a.sortKey));
    final total = unread.fold(0, (n, c) => n + c.unreadCount);
    final requests = ref.watch(incomingFriendRequestsProvider);
    if (total == 0 && requests == 0) return const SizedBox.shrink();

    final muted = context.palette.mutedForeground;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.mail, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr(Keys.homeInboxTitle), style: context.text.titleSmall),
                        if (total > 0)
                          Text(
                            context.trPlural(Keys.homeInboxUnread, total),
                            style: context.text.bodySmall?.copyWith(color: context.colors.primary),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/gifts?tab=chats'),
                    child: Text(context.tr(Keys.homeInboxSeeAll)),
                  ),
                ],
              ),
            ),
            for (final c in unread.take(_maxRows)) _InboxRow(conversation: c, myId: me),
            if (unread.length > _maxRows)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  context.trPlural(Keys.homeInboxMore, unread.length - _maxRows),
                  style: context.text.bodySmall?.copyWith(color: muted),
                ),
              ),
            if (requests > 0) ...[
              if (unread.isNotEmpty) const Divider(indent: 16, endIndent: 16),
              InkWell(
                onTap: () => context.push('/friends'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Row(
                    children: [
                      Icon(LucideIcons.userPlus, size: 18, color: context.colors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.trPlural(Keys.chatFriendRequests, requests),
                          style: context.text.bodyMedium,
                        ),
                      ),
                      Icon(LucideIcons.chevronRight, size: 16, color: muted),
                    ],
                  ),
                ),
              ),
            ] else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _InboxRow extends ConsumerWidget {
  const _InboxRow({required this.conversation, required this.myId});

  final Conversation conversation;
  final String? myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conversation;
    final last = c.lastMessage;
    final typing = ref.watch(conversationTypingProvider(c.id));
    final muted = context.palette.mutedForeground;
    final preview = typing.isNotEmpty
        ? (c.isGroup ? ChatFormat.typing(typing.values) : context.tr(Keys.chatTypingSelf))
        : last == null
        ? ''
        : c.isGroup && last.senderId != myId && last.senderName.isNotEmpty
        ? context.tr(Keys.chatPreviewSender, {'name': last.senderName.split(' ').first, 'text': last.preview})
        : last.preview;

    return InkWell(
      onTap: () => context.push('/chats/${c.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            ConversationAvatar(conversation: c, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: typing.isNotEmpty ? context.colors.primary : muted,
                      fontStyle: typing.isNotEmpty ? FontStyle.italic : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (last != null)
                  Text(ChatFormat.listTime(last.createdAt), style: context.text.labelSmall?.copyWith(color: muted)),
                const SizedBox(height: 4),
                CountBadge(count: c.unreadCount),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
