import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import '../groups/invite_widgets.dart';
import 'chat_widgets.dart';
import 'conversations_screen.dart';

String friendRequestMessage(FriendRequestResult r, String name) => switch (r) {
  FriendRequestResult.sent => 'Pedido enviado a $name.',
  FriendRequestResult.accepted => 'Tu e $name já são amigos. 🎉',
  FriendRequestResult.alreadyFriends => 'Tu e $name já são amigos.',
  FriendRequestResult.alreadySent => 'Já enviaste um pedido a $name.',
  FriendRequestResult.self => 'Não te podes adicionar a ti próprio.',
  FriendRequestResult.notFound => 'Esta conta já não existe.',
};

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
              title: Text('Conversar com ${f.firstName}'),
              onTap: () => Navigator.pop(ctx, 'chat'),
            ),
            ListTile(
              leading: Icon(LucideIcons.userMinus, color: ctx.colors.error),
              title: Text('Remover dos amigos', style: TextStyle(color: ctx.colors.error)),
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
        title: 'Remover ${f.firstName}?',
        message: 'Deixam de ser amigos. A conversa privada fica, mas sem novas mensagens.',
        confirm: 'Remover',
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
      appBar: AppBar(title: const Text('Amigos')),
      body: RefreshIndicator(
        onRefresh: ctrl.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            Text('Adicionar amigo', style: AppTheme.display(context, size: 22)),
            const SizedBox(height: 4),
            Text(
              'Procura pelo email, telemóvel ou @username. Amigos conversam em privado e são convidados para grupos com um toque.',
              style: context.text.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 12),
            ContactLookup(
              actionLabel: 'Adicionar',
              onAction: (user) async => friendRequestMessage(await ctrl.request(user.userId), user.name),
            ),
            if (list.incoming.isNotEmpty) ...[
              SectionTitle('Pedidos recebidos · ${list.incoming.length}', padding: const EdgeInsets.fromLTRB(4, 28, 0, 8)),
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
                          tooltip: 'Recusar',
                          onPressed: () => runGuarded(context, () => ctrl.respond(r, accept: false)),
                          icon: Icon(LucideIcons.x, color: muted),
                        ),
                        FilledButton(
                          onPressed: () => runGuarded(
                            context,
                            () => ctrl.respond(r, accept: true),
                            success: 'Tu e ${r.user.firstName} já são amigos. 🎉',
                          ),
                          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
                          child: const Text('Aceitar'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            SectionTitle(
              list.friends.isEmpty ? 'Amigos' : 'Amigos · ${list.friends.length}',
              padding: const EdgeInsets.fromLTRB(4, 28, 0, 8),
            ),
            if (async.isLoading && !async.hasValue)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)))
            else if (list.friends.isEmpty)
              Text('Ainda não tens amigos na Birthdayly.', style: TextStyle(color: muted))
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, f) in list.friends.indexed) ...[
                      if (i > 0) const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        leading: UserAvatar(user: f),
                        title: Text(f.name),
                        subtitle: f.username.isEmpty ? null : Text('@${f.username}'),
                        trailing: IconButton(
                          tooltip: 'Conversar',
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
              SectionTitle('Pedidos enviados', padding: const EdgeInsets.fromLTRB(4, 28, 0, 8)),
              for (final r in list.outgoing)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: UserAvatar(user: r.user),
                  title: Text(r.user.name),
                  subtitle: const Text('À espera de resposta'),
                  trailing: TextButton(
                    onPressed: () => runGuarded(context, () => ctrl.remove(r.user.userId), success: 'Pedido cancelado.'),
                    child: const Text('Cancelar'),
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
