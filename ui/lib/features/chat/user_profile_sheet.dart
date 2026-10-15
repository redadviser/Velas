import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/errors.dart';
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import 'chat_widgets.dart';
import 'conversations_list.dart';
import 'friends_screen.dart';

/// Perfil de outra pessoa (ao tocar no avatar no chat): fotografia, nome e o
/// estado da amizade — pedir, aceitar, cancelar ou enviar mensagem.
Future<void> showUserProfileSheet(BuildContext context, ChatUser user, {bool showMessageButton = true}) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _UserProfileSheet(user: user, showMessageButton: showMessageButton),
    );

class _UserProfileSheet extends ConsumerStatefulWidget {
  const _UserProfileSheet({required this.user, required this.showMessageButton});

  final ChatUser user;
  final bool showMessageButton;

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

    Widget action;
    if (u.userId == me) {
      action = const Pill(label: 'És tu');
    } else if (isFriend) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Pill(
              icon: LucideIcons.userCheck,
              label: 'Amigos',
              background: context.palette.success.withValues(alpha: 0.14),
              foreground: context.palette.success,
            ),
          ),
          if (widget.showMessageButton) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      Navigator.pop(context);
                      openDirectChat(context, ref, u.userId);
                    },
              icon: const Icon(LucideIcons.messageCircle, size: 18),
              label: const Text('Enviar mensagem'),
            ),
          ],
        ],
      );
    } else if (incoming != null) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${u.firstName} quer ser teu amigo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _run(() => ctrl.respond(incoming, accept: false)),
                  child: const Text('Recusar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => ctrl.respond(incoming, accept: true),
                          success: 'Tu e ${u.firstName} já são amigos. 🎉',
                        ),
                  child: const Text('Aceitar'),
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
            'Pedido de amizade enviado.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => _run(() => ctrl.remove(u.userId), success: 'Pedido cancelado.'),
            child: const Text('Cancelar pedido'),
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
        label: const Text('Adicionar amigo'),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: UserAvatar(user: u, size: 88)),
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
          ],
        ),
      ),
    );
  }
}
