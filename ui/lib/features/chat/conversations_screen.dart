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
import 'chat_widgets.dart';

/// Separador "Conversas": chats dos grupos e privados com amigos.
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(chatRepositoryProvider) != null;
    final conversations = ref.watch(conversationsProvider);
    final requests = ref.watch(incomingFriendRequestsProvider);
    final me = ref.watch(currentUserProvider)?.id;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
      child: Row(
        children: [
          Expanded(child: Text('Conversas', style: AppTheme.display(context, size: 30))),
          if (available)
            IconButton(
              tooltip: 'Amigos',
              onPressed: () => context.push('/friends'),
              icon: Badge(
                isLabelVisible: requests > 0,
                label: Text('$requests'),
                child: const Icon(LucideIcons.usersRound, size: 22),
              ),
            ),
        ],
      ),
    );

    if (!available) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: ListView(
            children: [
              header,
              const EmptyState(
                icon: LucideIcons.cloudOff,
                title: 'Conversas precisam do servidor',
                message: 'No modo local não há outras pessoas com quem falar. Entra com uma conta para conversar.',
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-chats',
        onPressed: () => startDirectChat(context, ref),
        icon: const Icon(LucideIcons.messageCirclePlus, size: 20),
        label: const Text('Nova conversa'),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(conversationsProvider.notifier).refresh();
            await ref.read(friendsProvider.notifier).refresh();
          },
          child: switch (conversations) {
            AsyncError(:final error) when !conversations.hasValue => ListView(
              children: [header, ErrorRetry(error: error, onRetry: () => ref.invalidate(conversationsProvider))],
            ),
            AsyncValue(:final value?) => ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                header,
                if (requests > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
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
                if (value.isEmpty)
                  const EmptyState(
                    icon: LucideIcons.messagesSquare,
                    title: 'Ainda sem conversas',
                    message:
                        'Cada prenda em grupo tem a sua conversa. Adiciona amigos para falarem também em privado.',
                  )
                else
                  for (final c in value) ConversationTile(conversation: c, myId: me),
              ],
            ),
            _ => ListView(
              children: [header, const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)))],
            ),
          },
        ),
      ),
    );
  }
}

class ConversationTile extends StatelessWidget {
  const ConversationTile({super.key, required this.conversation, required this.myId});

  final Conversation conversation;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final last = c.lastMessage;
    final unread = c.unreadCount > 0;
    final muted = context.palette.mutedForeground;
    final who = last == null
        ? ''
        : last.senderId == myId
        ? 'Tu: '
        : c.isGroup && last.senderName.isNotEmpty
        ? '${last.senderName.split(' ').first}: '
        : '';
    final preview = last == null
        ? (c.isGroup ? 'Prenda para ${c.celebrantName ?? ''} · combinem aqui' : 'Diz olá 👋')
        : '$who${last.preview}';

    return InkWell(
      onTap: () => context.push('/chats/${c.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          children: [
            ConversationAvatar(conversation: c),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.titleSmall?.copyWith(fontWeight: unread ? FontWeight.w800 : null),
                        ),
                      ),
                      if (last != null)
                        Text(
                          Fmt.chatTime(last.createdAt),
                          style: context.text.labelSmall?.copyWith(
                            color: unread ? context.colors.primary : muted,
                            fontWeight: unread ? FontWeight.w700 : null,
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
                            color: unread ? context.colors.onSurface : muted,
                            fontStyle: last?.deleted ?? false ? FontStyle.italic : null,
                          ),
                        ),
                      ),
                      if (unread) ...[const SizedBox(width: 8), CountBadge(count: c.unreadCount)],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
