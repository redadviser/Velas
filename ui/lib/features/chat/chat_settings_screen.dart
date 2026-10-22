import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants.dart';
import '../../core/i18n/translations.dart';
import '../../core/chat_providers.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../services/notification_service.dart';

/// Definições gerais das conversas: privacidade e notificações (como no
/// WhatsApp). Ficam no perfil, no servidor, e valem em todos os dispositivos.
class ChatSettingsScreen extends ConsumerWidget {
  const ChatSettingsScreen({super.key});

  Future<void> _save(BuildContext context, WidgetRef ref, UserProfile updated) =>
      runGuarded(context, () => ref.read(authRepositoryProvider).updateProfile(updated));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Scaffold();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr(Keys.chatSettingsTitle))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          SectionTitle(context.tr(Keys.chatSettingsPrivacy), padding: const EdgeInsets.fromLTRB(4, 8, 0, 8)),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _Switch(
                  icon: LucideIcons.radio,
                  title: context.tr(Keys.chatSettingsPresenceTitle),
                  hint: context.tr(Keys.chatSettingsPresenceHint),
                  value: user.showPresence,
                  onChanged: (v) => _save(context, ref, user.copyWith(showPresence: v)),
                ),
                const Divider(indent: 16, endIndent: 16),
                _Switch(
                  icon: LucideIcons.checkCheck,
                  title: context.tr(Keys.chatSettingsReceiptsTitle),
                  hint: context.tr(Keys.chatSettingsReceiptsHint),
                  value: user.readReceipts,
                  onChanged: (v) => _save(context, ref, user.copyWith(readReceipts: v)),
                ),
                const Divider(indent: 16, endIndent: 16),
                _Switch(
                  icon: LucideIcons.ellipsis,
                  title: context.tr(Keys.chatSettingsTypingTitle),
                  hint: context.tr(Keys.chatSettingsTypingHint),
                  value: user.typingIndicator,
                  onChanged: (v) => _save(context, ref, user.copyWith(typingIndicator: v)),
                ),
              ],
            ),
          ),
          SectionTitle(context.tr(Keys.chatSettingsNotifications), padding: const EdgeInsets.fromLTRB(4, 24, 0, 8)),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _Switch(
                  icon: LucideIcons.bell,
                  title: context.tr(Keys.chatSettingsMessagesTitle),
                  hint: context.tr(Keys.chatSettingsMessagesHint),
                  value: user.messageNotifications,
                  onChanged: (v) async {
                    // Ao ligar, pede autorização ao sistema (se ainda não houver).
                    if (v) await NotificationService.instance.requestPermission().catchError((_) => false);
                    if (context.mounted) await _save(context, ref, user.copyWith(messageNotifications: v));
                  },
                ),
                const Divider(indent: 16, endIndent: 16),
                _Switch(
                  icon: LucideIcons.messageSquareText,
                  title: context.tr(Keys.chatSettingsPreviewsTitle),
                  hint: context.tr(Keys.chatSettingsPreviewsHint),
                  value: user.messagePreviews,
                  onChanged: user.messageNotifications
                      ? (v) => _save(context, ref, user.copyWith(messagePreviews: v))
                      : null,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(
              context.tr(Keys.chatSettingsWhileOpen),
              style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
            ),
          ),
          SectionTitle(context.tr(Keys.friendsTitle), padding: const EdgeInsets.fromLTRB(4, 24, 0, 8)),
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(LucideIcons.usersRound),
              title: Text(context.tr(Keys.friendsTitle)),
              trailing: Icon(LucideIcons.chevronRight, size: 18, color: context.palette.mutedForeground),
              onTap: () => context.push('/friends'),
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(LucideIcons.ban),
              title: const Text('Bloqueados'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((ref.watch(blockedUsersProvider).value ?? const []).isNotEmpty)
                    Text(
                      '${ref.watch(blockedUsersProvider).value!.length}',
                      style: TextStyle(color: context.palette.mutedForeground),
                    ),
                  const SizedBox(width: 4),
                  Icon(LucideIcons.chevronRight, size: 18, color: context.palette.mutedForeground),
                ],
              ),
              onTap: () => context.push('/chat-settings/blocked'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.icon, required this.title, required this.hint, required this.value, this.onChanged});

  final IconData icon;
  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      secondary: Icon(icon, size: 20),
      title: Text(title),
      subtitle: Text(hint, style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground)),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
    );
  }
}
