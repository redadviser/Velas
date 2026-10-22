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
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import 'chat_format.dart';
import 'chat_widgets.dart';
import 'user_profile_sheet.dart';

enum _Mute { hours8, week, always, off }

/// Detalhes de uma conversa (como a "info" do WhatsApp): silenciar, fixar,
/// participantes e atalhos para a prenda ou para o perfil da outra pessoa.
class ConversationInfoScreen extends ConsumerWidget {
  const ConversationInfoScreen({super.key, required this.conversationId});

  final String conversationId;

  Future<void> _mute(BuildContext context, WidgetRef ref, Conversation c) async {
    final choice = await showModalBottomSheet<_Mute>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(ctx.tr(Keys.chatInfoMute), style: AppTheme.display(ctx, size: 22)),
            ),
            for (final (option, key) in [
              (_Mute.hours8, Keys.chatInfoMute8h),
              (_Mute.week, Keys.chatInfoMute1w),
              (_Mute.always, Keys.chatInfoMuteAlways),
            ])
              ListTile(
                leading: const Icon(LucideIcons.bellOff),
                title: Text(ctx.tr(key)),
                onTap: () => Navigator.pop(ctx, option),
              ),
            if (c.isMuted)
              ListTile(
                leading: const Icon(LucideIcons.bellRing),
                title: Text(ctx.tr(Keys.chatInfoUnmute)),
                onTap: () => Navigator.pop(ctx, _Mute.off),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final now = DateTime.now();
    final until = switch (choice) {
      _Mute.hours8 => now.add(const Duration(hours: 8)),
      _Mute.week => now.add(const Duration(days: 7)),
      _Mute.always => Conversation.mutedForever,
      _Mute.off => null,
    };
    await runGuarded(
      context,
      () => ref.read(conversationsProvider.notifier).setPrefs(conversationId, mutedUntil: () => until),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatProvider(conversationId));
    final me = ref.watch(currentUserProvider)?.id;
    final c =
        ref.watch(conversationsProvider).value?.where((x) => x.id == conversationId).firstOrNull ?? state.conversation;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    final other = c.otherUser;
    final participants = state.conversation?.participants ?? const <Participant>[];
    final muted = context.palette.mutedForeground;
    final otherPresence = other == null ? null : ref.watch(userPresenceProvider(other.userId));
    final subtitle = c.isGroup
        ? (c.celebrantName == null ? null : context.tr(Keys.chatHeaderGiftFor, {'name': c.celebrantName}))
        : otherPresence == null
        ? null
        : ChatFormat.presence(online: otherPresence.online, lastSeenAt: otherPresence.lastSeenAt);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr(Keys.chatInfoTitle))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Center(
            child: ZoomablePhoto(
              url: c.isGroup ? c.photoUrl : other?.photoUrl,
              title: c.title,
              child: ConversationAvatar(conversation: c, size: 88),
            ),
          ),
          const SizedBox(height: 14),
          Text(c.title, textAlign: TextAlign.center, style: AppTheme.display(context, size: 24)),
          if (other != null && other.username.isNotEmpty)
            Text(
              '@${other.username}',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(
                  color: otherPresence?.online ?? false ? context.palette.success : muted,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Center(
            child: c.isGroup && c.groupId != null
                ? OutlinedButton.icon(
                    onPressed: () => context.push('/groups/${c.groupId}'),
                    icon: const Icon(LucideIcons.gift, size: 18),
                    label: Text(context.tr(Keys.chatHeaderSeeGift)),
                  )
                : other == null
                ? const SizedBox.shrink()
                : OutlinedButton.icon(
                    onPressed: () => showUserProfileSheet(context, other, showMessageButton: false),
                    icon: const Icon(LucideIcons.user, size: 18),
                    label: Text(context.tr(Keys.chatInfoViewProfile)),
                  ),
          ),
          const SizedBox(height: 20),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(c.isMuted ? LucideIcons.bellOff : LucideIcons.bell),
                  title: Text(context.tr(Keys.chatInfoMute)),
                  subtitle: Text(
                    !c.isMuted
                        ? context.tr(Keys.chatInfoNotificationsOn)
                        : c.isMutedForever
                        ? context.tr(Keys.chatInfoMutedAlways)
                        : context.tr(Keys.chatInfoMutedUntil, {'date': ChatFormat.until(c.mutedUntil!)}),
                    style: TextStyle(color: muted),
                  ),
                  trailing: Icon(LucideIcons.chevronRight, size: 18, color: muted),
                  onTap: () => _mute(context, ref, c),
                ),
                const Divider(indent: 16, endIndent: 16),
                SwitchListTile(
                  secondary: const Icon(LucideIcons.pin),
                  title: Text(context.tr(Keys.chatInfoPin)),
                  subtitle: Text(context.tr(Keys.chatInfoPinHint), style: TextStyle(color: muted)),
                  value: c.pinned,
                  onChanged: (v) => runGuarded(
                    context,
                    () => ref.read(conversationsProvider.notifier).setPrefs(conversationId, pinned: v),
                  ),
                ),
              ],
            ),
          ),
          if (c.isGroup && participants.isNotEmpty) ...[
            SectionTitle(
              context.tr(Keys.chatInfoMembers, {'count': participants.length}),
              padding: const EdgeInsets.fromLTRB(4, 24, 0, 8),
            ),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, p) in participants.indexed) ...[
                    if (i > 0) const Divider(indent: 16, endIndent: 16),
                    _Member(participant: p, isMe: p.user.userId == me),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Member extends ConsumerWidget {
  const _Member({required this.participant, required this.isMe});

  final Participant participant;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = participant.user;
    final p = ref.watch(userPresenceProvider(u.userId));
    final status = isMe ? null : ChatFormat.presence(online: p.online, lastSeenAt: p.lastSeenAt);
    return ListTile(
      leading: PresenceAvatar(user: u),
      title: Text(isMe ? '${u.name} (${context.tr(Keys.chatInfoYou)})' : u.name),
      subtitle: status == null && u.username.isEmpty
          ? null
          : Text(
              status ?? '@${u.username}',
              style: TextStyle(color: p.online && !isMe ? context.palette.success : context.palette.mutedForeground),
            ),
      onTap: isMe ? null : () => showUserProfileSheet(context, u),
    );
  }
}
