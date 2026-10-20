import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import '../auth/auth_widgets.dart';
import '../chat/chat_widgets.dart';

/// O amigo que tem este nome, se só houver um (nome completo ou, não havendo,
/// primeiro nome).
ChatUser? matchingFriend(String name, Iterable<ChatUser> friends) {
  String norm(String s) => s.trim().toLowerCase();
  final first = name.trim().split(RegExp(r'\s+')).first;
  if (norm(name).isEmpty) return null;
  final full = friends.where((f) => norm(f.name) == norm(name)).toList();
  if (full.length == 1) return full.first;
  final byFirst = friends.where((f) => norm(f.firstName) == norm(first)).toList();
  return byFirst.length == 1 ? byFirst.first : null;
}

/// O amigo ligado a um aniversário, se ainda for amigo.
ChatUser? linkedFriend(WidgetRef ref, String? userId) {
  if (userId == null) return null;
  return ref.watch(friendsProvider).value?.friends.where((f) => f.userId == userId).firstOrNull;
}

Future<ChatUser?> pickFriend(BuildContext context, List<ChatUser> friends, {required String title}) =>
    showModalBottomSheet<ChatUser>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(title, style: AppTheme.display(ctx, size: 22)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in friends)
                      ListTile(
                        leading: UserAvatar(user: f, size: 36),
                        title: Text(f.name),
                        subtitle: f.username.isEmpty ? null : Text('@${f.username}'),
                        onTap: () => Navigator.pop(ctx, f),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

/// No formulário do aniversário: ligar a pessoa a um amigo que já está na
/// Birthdayly. Sugere o amigo com o mesmo nome. Só aparece com servidor e
/// quando há amigos (ou já há ligação).
class LinkedFriendField extends ConsumerWidget {
  const LinkedFriendField({
    super.key,
    required this.linkedUserId,
    required this.personName,
    required this.onChanged,
    this.personId,
  });

  final String? linkedUserId;
  final String personName;
  final String? personId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(chatRepositoryProvider) == null) return const SizedBox.shrink();
    final friends = ref.watch(friendsProvider).value?.friends ?? const <ChatUser>[];
    // Cada amigo só fica ligado a um aniversário.
    final taken = {
      for (final p in ref.watch(dataProvider).people)
        if (p.id != personId && p.linkedUserId != null) p.linkedUserId!,
    };
    final available = friends.where((f) => !taken.contains(f.userId)).toList();
    final linked = linkedUserId == null ? null : friends.where((f) => f.userId == linkedUserId).firstOrNull;
    if (linkedUserId == null && available.isEmpty) return const SizedBox.shrink();

    final muted = context.palette.mutedForeground;
    Future<void> choose() async {
      final f = await pickFriend(context, available, title: 'Quem é na Birthdayly?');
      if (f != null) onChanged(f.userId);
    }

    final Widget body;
    if (linkedUserId != null) {
      body = AppCard(
        onTap: choose,
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            if (linked != null) UserAvatar(user: linked, size: 36) else const Icon(LucideIcons.userCheck, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(linked?.name ?? 'Amigo da Birthdayly', style: context.text.bodyLarge),
                  if (linked != null && linked.username.isNotEmpty)
                    Text('@${linked.username}', style: context.text.bodySmall?.copyWith(color: muted)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Desligar',
              icon: Icon(LucideIcons.x, size: 18, color: muted),
              onPressed: () => onChanged(null),
            ),
          ],
        ),
      );
    } else {
      final suggestion = matchingFriend(personName, available);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (suggestion != null)
            AppCard(
              color: context.palette.accent,
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  UserAvatar(user: suggestion, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${suggestion.name} está na Birthdayly. É esta pessoa?',
                      style: context.text.bodyMedium?.copyWith(color: context.palette.accentForeground),
                    ),
                  ),
                  TextButton(onPressed: () => onChanged(suggestion.userId), child: const Text('Ligar')),
                ],
              ),
            ),
          if (suggestion != null) const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: choose,
            icon: const Icon(LucideIcons.userPlus, size: 18),
            label: const Text('Ligar a um amigo da Birthdayly'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const FieldLabel('Na Birthdayly'),
        body,
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Text(
            'Ligado a um amigo, os parabéns podem ir diretamente para o mural e a conversa dele.',
            style: context.text.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}
