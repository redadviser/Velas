import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/constants.dart';
import '../../core/i18n/translations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/widgets/common.dart';
import '../../core/wishlist_providers.dart';
import '../../data/models/chat_models.dart';
import '../gifts/wishlist_widgets.dart';
import 'chat_widgets.dart';
import 'friends_screen.dart';
import 'safety.dart';

/// Perfil de outra pessoa (no chat ou nos amigos): fotografia, nome, o estado
/// da amizade e, se for amiga, os gostos e a lista de desejos.
Future<void> showUserProfileSheet(BuildContext context, ChatUser user) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _UserProfileSheet(user: user),
);

class _UserProfileSheet extends ConsumerStatefulWidget {
  const _UserProfileSheet({required this.user});

  final ChatUser user;

  @override
  ConsumerState<_UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends ConsumerState<_UserProfileSheet> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    await runGuarded(context, action, success: success);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _removeFriend(ChatUser u) async {
    final ok = await confirmDialog(
      context,
      title: context.tr(Keys.friendsRemoveTitle, {'name': u.firstName}),
      message: context.tr(Keys.friendsRemoveMessage),
      confirm: context.tr(Keys.commonRemove),
    );
    if (!ok || !mounted) return;
    final navigator = Navigator.of(context);
    await _run(() => ref.read(friendsProvider.notifier).remove(u.userId));
    if (mounted && !ref.read(friendsProvider).requireValue.isFriend(u.userId)) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final me = ref.watch(currentUserProvider)?.id;
    final friends = ref.watch(friendsProvider).value ?? FriendsList.empty;
    final ctrl = ref.read(friendsProvider.notifier);
    final incoming = friends.incoming.where((r) => r.user.userId == u.userId).firstOrNull;
    final outgoing = friends.outgoing.where((r) => r.user.userId == u.userId).firstOrNull;
    final isFriend = friends.isFriend(u.userId);
    final muted = context.palette.mutedForeground;

    final blocked = ref.watch(blockedIdsProvider).contains(u.userId);
    Widget action;
    if (u.userId == me) {
      action = Pill(label: context.tr(Keys.profileSheetYou));
    } else if (blocked) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('Bloqueaste {name}.', {'name': u.firstName}),
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => ref.read(blockedUsersProvider.notifier).unblock(u.userId),
                    success: context.tr('Desbloqueaste {name}.', {'name': u.firstName}),
                  ),
            child: Text(context.tr('Desbloquear')),
          ),
        ],
      );
    } else if (isFriend) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Pill(
              icon: LucideIcons.userCheck,
              label: context.tr(Keys.profileSheetFriends),
              background: context.palette.success.withValues(alpha: 0.14),
              foreground: context.palette.success,
            ),
          ),
          _FriendWishes(user: u),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _busy ? null : () => _removeFriend(u),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            icon: const Icon(LucideIcons.userMinus, size: 18),
            label: Text(context.tr(Keys.friendsRemoveAction)),
          ),
        ],
      );
    } else if (incoming != null) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(Keys.profileSheetWantsFriend, {'name': u.firstName}),
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _run(() => ctrl.respond(incoming, accept: false)),
                  child: Text(context.tr(Keys.commonDecline)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => ctrl.respond(incoming, accept: true),
                          success: context.tr(Keys.friendsResultAccepted, {'name': u.firstName}),
                        ),
                  child: Text(context.tr(Keys.commonAccept)),
                ),
              ),
            ],
          ),
        ],
      );
    } else if (outgoing != null) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(Keys.profileSheetRequestSent),
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(() => ctrl.remove(u.userId), success: context.tr(Keys.friendsRequestCancelled)),
            child: Text(context.tr(Keys.profileSheetCancelRequest)),
          ),
        ],
      );
    } else {
      action = FilledButton.icon(
        onPressed: _busy
            ? null
            : () async {
                final messenger = ScaffoldMessenger.of(context);
                setState(() => _busy = true);
                try {
                  final r = await ctrl.request(u.userId);
                  messenger.showSnackBar(SnackBar(content: Text(friendRequestMessage(r, u.firstName))));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        icon: _busy
            ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(LucideIcons.userPlus, size: 18),
        label: Text(context.tr(Keys.profileSheetAddFriend)),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: ZoomablePhoto(
                url: u.photoUrl,
                title: u.name,
                child: UserAvatar(user: u, size: 88),
              ),
            ),
            const SizedBox(height: 14),
            Text(u.name, textAlign: TextAlign.center, style: AppTheme.display(context, size: 24)),
            if (u.username.isNotEmpty)
              Text(
                '@${u.username}',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
            const SizedBox(height: 20),
            action,
            if (u.userId != me && ref.watch(apiClientProvider) != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      showReportSheet(context, ref, u);
                    },
                    style: TextButton.styleFrom(foregroundColor: muted),
                    icon: const Icon(LucideIcons.flag, size: 16),
                    label: Text(context.tr('Denunciar')),
                  ),
                  if (!blocked)
                    TextButton.icon(
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        if (await confirmBlock(context, ref, u)) navigator.pop();
                      },
                      style: TextButton.styleFrom(foregroundColor: context.colors.error),
                      icon: const Icon(LucideIcons.ban, size: 16),
                      label: Text(context.tr('Bloquear')),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Gostos e lista de desejos de um amigo (vêm do servidor).
class _FriendWishes extends ConsumerWidget {
  const _FriendWishes({required this.user});

  final ChatUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(friendWishlistProvider(user.userId));
    final muted = context.palette.mutedForeground;
    final data = async.value;
    if (data == null) {
      return async.isLoading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          : const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.interests.isNotEmpty) ...[
          SectionTitle(context.tr('Gostos e hobbies'), padding: const EdgeInsets.fromLTRB(4, 24, 0, 8)),
          InterestChips(keys: data.interests),
        ],
        SectionTitle(context.tr('Lista de desejos'), padding: const EdgeInsets.fromLTRB(4, 24, 0, 6)),
        if (data.items.isEmpty)
          Text(
            context.tr('{name} ainda não pôs nada na lista.', {'name': user.firstName}),
            style: TextStyle(color: muted),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, w) in data.items.indexed) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  WishRow(item: w),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
