import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/constants.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import '../groups/invite_widgets.dart';
import 'chat_format.dart';
import 'chat_widgets.dart';
import 'conversations_list.dart';

String friendRequestMessage(FriendRequestResult r, String name) => tr(
  switch (r) {
    FriendRequestResult.sent => Keys.friendsResultSent,
    FriendRequestResult.accepted => Keys.friendsResultAccepted,
    FriendRequestResult.alreadyFriends => Keys.friendsResultAlreadyFriends,
    FriendRequestResult.alreadySent => Keys.friendsResultAlreadySent,
    FriendRequestResult.self => Keys.friendsResultSelf,
    FriendRequestResult.notFound => Keys.friendsResultNotFound,
  },
  {'name': name},
);

class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  Future<void> _friendMenu(BuildContext context, WidgetRef ref, ChatUser f) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.messageCircle),
              title: Text(ctx.tr(Keys.friendsChatWith, {'name': f.firstName})),
              onTap: () => Navigator.pop(ctx, 'chat'),
            ),
            ListTile(
              leading: Icon(LucideIcons.userMinus, color: ctx.colors.error),
              title: Text(ctx.tr(Keys.friendsRemoveAction), style: TextStyle(color: ctx.colors.error)),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'chat') {
      await openDirectChat(context, ref, f.userId);
    } else if (action == 'remove') {
      final ok = await confirmDialog(
        context,
        title: context.tr(Keys.friendsRemoveTitle, {'name': f.firstName}),
        message: context.tr(Keys.friendsRemoveMessage),
        confirm: context.tr(Keys.commonRemove),
      );
      if (ok && context.mounted) await runGuarded(context, () => ref.read(friendsProvider.notifier).remove(f.userId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(friendsProvider);
    final list = async.value ?? FriendsList.empty;
    final ctrl = ref.read(friendsProvider.notifier);
    final muted = context.palette.mutedForeground;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr(Keys.friendsTitle))),
      body: RefreshIndicator(
        onRefresh: ctrl.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            Text(context.tr(Keys.friendsAddTitle), style: AppTheme.display(context, size: 22)),
            const SizedBox(height: 4),
            Text(context.tr(Keys.friendsAddHint), style: context.text.bodySmall?.copyWith(color: muted)),
            const SizedBox(height: 12),
            ContactLookup(
              actionLabel: context.tr(Keys.friendsAddAction),
              onAction: (user) async => friendRequestMessage(await ctrl.request(user.userId), user.name),
            ),
            if (list.incoming.isNotEmpty) ...[
              SectionTitle(
                context.tr(Keys.friendsIncoming, {'count': list.incoming.length}),
                padding: const EdgeInsets.fromLTRB(4, 28, 0, 8),
              ),
              for (final r in list.incoming)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    child: Row(
                      children: [
                        UserAvatar(user: r.user),
                        const SizedBox(width: 12),
                        Expanded(child: _Name(user: r.user)),
                        IconButton(
                          tooltip: context.tr(Keys.commonDecline),
                          onPressed: () => runGuarded(context, () => ctrl.respond(r, accept: false)),
                          icon: Icon(LucideIcons.x, color: muted),
                        ),
                        FilledButton(
                          onPressed: () => runGuarded(
                            context,
                            () => ctrl.respond(r, accept: true),
                            success: context.tr(Keys.friendsResultAccepted, {'name': r.user.firstName}),
                          ),
                          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
                          child: Text(context.tr(Keys.commonAccept)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            SectionTitle(
              list.friends.isEmpty
                  ? context.tr(Keys.friendsList)
                  : context.tr(Keys.friendsListCount, {'count': list.friends.length}),
              padding: const EdgeInsets.fromLTRB(4, 28, 0, 8),
            ),
            if (async.isLoading && !async.hasValue)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
              )
            else if (list.friends.isEmpty)
              Text(context.tr(Keys.friendsEmpty), style: TextStyle(color: muted))
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, f) in list.friends.indexed) ...[
                      if (i > 0) const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        leading: PresenceAvatar(user: f),
                        title: Text(f.name),
                        subtitle: _FriendStatus(user: f),
                        trailing: IconButton(
                          tooltip: context.tr(Keys.friendsChat),
                          onPressed: () => openDirectChat(context, ref, f.userId),
                          icon: Icon(LucideIcons.messageCircle, color: context.colors.primary),
                        ),
                        onTap: () => _friendMenu(context, ref, f),
                      ),
                    ],
                  ],
                ),
              ),
            if (list.outgoing.isNotEmpty) ...[
              SectionTitle(context.tr(Keys.friendsOutgoing), padding: const EdgeInsets.fromLTRB(4, 28, 0, 8)),
              for (final r in list.outgoing)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: UserAvatar(user: r.user),
                  title: Text(r.user.name),
                  subtitle: Text(context.tr(Keys.friendsWaiting)),
                  trailing: TextButton(
                    onPressed: () => runGuarded(
                      context,
                      () => ctrl.remove(r.user.userId),
                      success: context.tr(Keys.friendsRequestCancelled),
                    ),
                    child: Text(context.tr(Keys.commonCancel)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Name extends StatelessWidget {
  const _Name({required this.user});

  final ChatUser user;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(user.name, style: context.text.titleSmall),
      if (user.username.isNotEmpty)
        Text('@${user.username}', style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground)),
    ],
  );
}

/// "Online", "Visto por último …" ou o @username.
class _FriendStatus extends ConsumerWidget {
  const _FriendStatus({required this.user});

  final ChatUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(userPresenceProvider(user.userId));
    context.translations;
    final status = ChatFormat.presence(online: p.online, lastSeenAt: p.lastSeenAt);
    final text = status ?? (user.username.isEmpty ? null : '@${user.username}');
    if (text == null) return const SizedBox.shrink();
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: p.online ? context.palette.success : context.palette.mutedForeground),
    );
  }
}
