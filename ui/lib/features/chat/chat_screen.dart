import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'chat_format.dart';
import 'chat_widgets.dart';
import 'composer.dart';
import 'media_panel.dart';
import 'message_bubble.dart';
import 'read_receipts.dart';
import 'user_profile_sheet.dart';

const quickReactions = ['❤️', '😂', '😮', '😢', '🎉', '👍'];

/// Mensagens seguidas da mesma pessoa com menos disto entre si ficam no mesmo bloco.
const _runGap = Duration(minutes: 5);

/// Avatares de "vista" mostrados debaixo de uma mensagem (o resto fica em "+N").
const _maxSeenAvatars = 5;

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scroll = ScrollController();
  ChatMessage? _replyTo;
  late final ConversationsController _conversations = ref.read(conversationsProvider.notifier);

  ChatController get _chat => ref.read(chatProvider(widget.conversationId).notifier);

  @override
  void initState() {
    super.initState();
    _conversations.setOpen(widget.conversationId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chat.setVisible(true);
    });
    _scroll.addListener(() {
      // A lista está invertida: "depois" é para as mensagens mais antigas.
      if (_scroll.position.extentAfter < 400) _chat.loadMore().catchError((_) {});
    });
  }

  @override
  void dispose() {
    _conversations.setOpen(null);
    _scroll.dispose();
    super.dispose();
  }

  String get _me => ref.read(currentUserProvider)?.id ?? '';

  Future<void> _actions(ChatMessage m, {required bool mine}) async {
    HapticFeedback.selectionClick();
    final canSave = m.kind != MessageKind.text && m.state == SendState.sent;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.state == SendState.sent)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final e in quickReactions)
                      _ReactionChoice(
                        emoji: e,
                        selected: m.reactionOf(_me) == e,
                        onTap: () => Navigator.pop(ctx, 'react:$e'),
                      ),
                    IconButton.filledTonal(
                      tooltip: ctx.tr(Keys.chatActionMoreEmoji),
                      onPressed: () => Navigator.pop(ctx, 'react-more'),
                      icon: const Icon(LucideIcons.plus, size: 20),
                    ),
                  ],
                ),
              ),
            if (m.state == SendState.sent)
              ListTile(
                leading: const Icon(LucideIcons.reply),
                title: Text(ctx.tr(Keys.chatActionReply)),
                onTap: () => Navigator.pop(ctx, 'reply'),
              ),
            if (mine && m.state == SendState.sent)
              ListTile(
                leading: const Icon(LucideIcons.eye),
                title: Text(ctx.tr(Keys.chatActionWhoSaw)),
                onTap: () => Navigator.pop(ctx, 'seen'),
              ),
            if (m.kind == MessageKind.text)
              ListTile(
                leading: const Icon(LucideIcons.copy),
                title: Text(ctx.tr(Keys.chatActionCopy)),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
            if (canSave)
              ListTile(
                leading: const Icon(LucideIcons.sticker),
                title: Text(ctx.tr(Keys.chatActionSaveSticker)),
                onTap: () => Navigator.pop(ctx, 'sticker'),
              ),
            if (m.state == SendState.failed) ...[
              ListTile(
                leading: const Icon(LucideIcons.refreshCw),
                title: Text(ctx.tr(Keys.chatActionRetry)),
                onTap: () => Navigator.pop(ctx, 'retry'),
              ),
              ListTile(
                leading: const Icon(LucideIcons.x),
                title: Text(ctx.tr(Keys.chatActionDiscard)),
                onTap: () => Navigator.pop(ctx, 'discard'),
              ),
            ],
            if (mine && m.state == SendState.sent)
              ListTile(
                leading: Icon(LucideIcons.trash2, color: ctx.colors.error),
                title: Text(ctx.tr(Keys.chatActionDeleteForAll), style: TextStyle(color: ctx.colors.error)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'reply':
        setState(() => _replyTo = m);
      case 'seen':
        _showSeenBy(m);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.body));
        if (mounted) showMessage(context, context.tr(Keys.chatCopied));
      case 'sticker':
        await runGuarded(
          context,
          () => ref.read(stickersProvider.notifier).saveFromMessage(m),
          success: context.tr(Keys.chatStickerSaved),
        );
      case 'retry':
        await _chat.retry(m).catchError((_) {});
      case 'discard':
        _chat.discard(m);
      case 'delete':
        final ok = await confirmDialog(
          context,
          title: context.tr(Keys.chatDeleteTitle),
          message: context.tr(Keys.chatDeleteMessage),
          confirm: context.tr(Keys.commonDelete),
        );
        if (ok && mounted) await runGuarded(context, () => _chat.delete(m));
      case 'react-more':
        final emoji = await _pickEmoji();
        if (emoji != null && mounted) await runGuarded(context, () => _chat.react(m, emoji));
      default:
        if (action.startsWith('react:')) await runGuarded(context, () => _chat.react(m, action.substring(6)));
    }
  }

  Future<String?> _pickEmoji() => showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: 340,
        child: EmojiPicker(onEmojiSelected: (_, e) => Navigator.pop(ctx, e.emoji), config: emojiConfig(ctx)),
      ),
    ),
  );

  /// "Vista por": quem viu a mensagem e quando.
  void _showSeenBy(ChatMessage m) {
    final participants = ref.read(chatProvider(widget.conversationId)).conversation?.participants ?? const [];
    final readers = ReadReceipts.readersOf(m, participants, _me);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(ctx.tr(Keys.chatSeenSheetTitle), style: AppTheme.display(ctx, size: 22)),
            ),
            if (readers.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Text(ctx.tr(Keys.chatSeenSheetNobody), style: TextStyle(color: ctx.palette.mutedForeground)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in readers)
                      ListTile(
                        leading: PresenceAvatar(user: p.user),
                        title: Text(p.user.name),
                        trailing: Text(
                          ChatFormat.seenAt(p.lastReadAt!),
                          style: ctx.text.bodySmall?.copyWith(color: ctx.palette.mutedForeground),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Perfil de quem enviou: com o @username dos participantes, se já tiverem carregado.
  void _openSender(ChatMessage m, ChatState state) {
    final id = m.senderId;
    if (id == null) return;
    final known = state.conversation?.participants.where((p) => p.user.userId == id).firstOrNull?.user;
    showUserProfileSheet(context, known ?? ChatUser(userId: id, name: m.senderName, photoUrl: m.senderPhotoUrl));
  }

  void _openMedia(ChatMessage m) {
    if (m.mediaUrl == null && m.localBytes == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _MediaViewer(
          message: m,
          onSaveSticker: m.state == SendState.sent
              ? () => ref.read(stickersProvider.notifier).saveFromMessage(m)
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider(widget.conversationId));
    final me = ref.watch(currentUserProvider)?.id ?? '';
    final typing = ref.watch(conversationTypingProvider(widget.conversationId));
    final summary =
        state.conversation ??
        ref.watch(conversationsProvider).value?.where((c) => c.id == widget.conversationId).firstOrNull;
    final isGroup = summary?.isGroup ?? false;
    final groupId = summary?.groupId;
    final group = groupId == null ? null : ref.watch(groupsProvider).value?.where((g) => g.id == groupId).firstOrNull;
    final other = summary?.otherUser;
    final friends = ref.watch(friendsProvider).value;
    final presence = ref.watch(presenceProvider);
    // Deixaram de ser amigos: a conversa fica, mas não se escreve.
    final blocked = summary != null && !isGroup && other != null && friends != null && !friends.isFriend(other.userId);

    final participants = state.conversation?.participants ?? const <Participant>[];
    final seenAt = ReadReceipts.positions(state.messages, participants, me);
    final typingUsers = [
      for (final MapEntry(key: id, value: name) in typing.entries)
        participants.where((p) => p.user.userId == id).firstOrNull?.user ?? ChatUser(userId: id, name: name),
    ];
    final extra = typingUsers.isEmpty ? 0 : 1; // o balão "a escrever" no fundo

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: summary == null
            ? null
            : InkWell(
                // Grupo: abre a prenda. Privada: o perfil da outra pessoa.
                onTap: groupId != null
                    ? () => context.push('/groups/$groupId')
                    : other == null
                    ? null
                    : () => showUserProfileSheet(context, other, showMessageButton: false),
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  children: [
                    ConversationAvatar(conversation: summary, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            summary.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleMedium,
                          ),
                          Text(
                            _subtitle(context, summary, participants, me, typing, presence),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall?.copyWith(
                              color: typing.isNotEmpty || (other != null && (presence[other.userId]?.online ?? false))
                                  ? context.colors.primary
                                  : context.palette.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        actions: [
          if (groupId != null)
            IconButton(
              tooltip: context.tr(Keys.chatHeaderSeeGift),
              onPressed: () => context.push('/groups/$groupId'),
              icon: const Icon(LucideIcons.gift, size: 20),
            ),
        ],
      ),
      body: Column(
        children: [
          if (group != null) _GiftBanner(group: group),
          Expanded(
            child: state.loading && state.messages.isEmpty
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                : state.error != null && state.messages.isEmpty
                ? ErrorRetry(error: state.error!, onRetry: _chat.load)
                : state.messages.isEmpty && typingUsers.isEmpty
                ? _EmptyChat(conversation: summary, group: group)
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.only(bottom: 10),
                    itemCount: state.messages.length + extra + (state.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (extra == 1 && index == 0) return _TypingBubble(users: typingUsers, isGroup: isGroup);
                      final i = index - extra;
                      final list = state.messages;
                      if (i == list.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        );
                      }
                      final m = list[i];
                      final older = i + 1 < list.length ? list[i + 1] : null;
                      final newer = i > 0 ? list[i - 1] : null;
                      final newDay = older == null ? !state.hasMore : !_sameDay(older.createdAt, m.createdAt);
                      final mine = m.senderId == me;
                      final readers = seenAt[m.id] ?? const [];
                      return Column(
                        children: [
                          if (newDay) _DaySeparator(date: m.createdAt),
                          MessageBubble(
                            key: ValueKey(m.id),
                            message: m,
                            myId: me,
                            isGroup: isGroup,
                            firstInRun: newDay || !_sameRun(older, m),
                            lastInRun: !_sameRun(m, newer),
                            seen: mine && ReadReceipts.seenByAll(m, participants, me),
                            onLongPress: () => _actions(m, mine: mine),
                            onOpenMedia: () => _openMedia(m),
                            onReact: m.state == SendState.sent
                                ? (e) => runGuarded(context, () => _chat.react(m, e))
                                : null,
                            onRetry: () => _chat.retry(m).catchError((_) {}),
                            onTapSender: mine ? null : () => _openSender(m, state),
                            onSwipeReply: blocked ? null : () => setState(() => _replyTo = m),
                          ),
                          if (readers.isNotEmpty) _SeenRow(readers: readers, onTap: () => _showSeenBy(m)),
                        ],
                      );
                    },
                  ),
          ),
          if (blocked)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  context.tr(Keys.chatBlocked),
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                ),
              ),
            )
          else
            Composer(
              conversationId: widget.conversationId,
              replyTo: _replyTo,
              onCancelReply: () => setState(() => _replyTo = null),
            ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _sameRun(ChatMessage? older, ChatMessage? newer) =>
      older != null &&
      newer != null &&
      older.senderId == newer.senderId &&
      _sameDay(older.createdAt, newer.createdAt) &&
      newer.createdAt.difference(older.createdAt) < _runGap;

  /// Por baixo do nome: quem está a escrever; numa privada, se está online
  /// ou quando foi visto; num grupo, quem participa e quantos estão online.
  String _subtitle(
    BuildContext context,
    Conversation c,
    List<Participant> participants,
    String me,
    Map<String, String> typing,
    Map<String, Presence> presence,
  ) {
    if (typing.isNotEmpty) return c.isGroup ? ChatFormat.typing(typing.values) : context.tr(Keys.chatTypingSelf);
    if (!c.isGroup) {
      final other = c.otherUser;
      final p = other == null ? null : presence[other.userId];
      final status = p == null ? null : ChatFormat.presence(online: p.online, lastSeenAt: p.lastSeenAt);
      if (status != null) return status;
      return other?.username.isNotEmpty ?? false ? '@${other!.username}' : context.tr(Keys.chatHeaderDirect);
    }
    final others = participants.where((p) => p.user.userId != me).toList();
    if (others.isEmpty) {
      return c.celebrantName == null
          ? context.tr(Keys.chatHeaderGroup)
          : context.tr(Keys.chatHeaderGiftFor, {'name': c.celebrantName});
    }
    final names = others.map((p) => p.user.firstName).toList();
    final members = names.length <= 3
        ? context.tr(Keys.chatHeaderMembers, {'names': names.join(', ')})
        : context.tr(Keys.chatHeaderMembersMore, {'names': names.take(3).join(', '), 'count': names.length - 3});
    final online = others.where((p) => presence[p.user.userId]?.online ?? false).length;
    return online == 0 ? members : '$members · ${context.tr(Keys.chatOnlineCount, {'count': online})}';
  }
}

/// "Está a escrever…": avatar(es) e três pontos, no fundo da conversa.
class _TypingBubble extends StatelessWidget {
  const _TypingBubble({required this.users, required this.isGroup});

  final List<ChatUser> users;
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: isGroup ? ChatFormat.typing(users.map((u) => u.name)) : context.tr(Keys.chatTypingSelf),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: users.length > 1 ? 44 : 30,
              height: 30,
              child: Stack(
                children: [
                  for (final (i, u) in users.take(2).indexed)
                    Positioned(
                      left: i * 14.0,
                      child: UserAvatar(user: u, size: 30),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: context.palette.muted,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                  bottomLeft: Radius.circular(5),
                ),
              ),
              child: const TypingDots(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatares pequenos de quem viu até esta mensagem (toque: "Vista por").
class _SeenRow extends StatelessWidget {
  const _SeenRow({required this.readers, required this.onTap});

  final List<Participant> readers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const size = 16.0;
    final shown = readers.take(_maxSeenAvatars).toList();
    final rest = readers.length - shown.length;
    return Align(
      alignment: Alignment.centerRight,
      child: Semantics(
        button: true,
        label: ChatFormat.seenBy(readers.map((p) => p.user).toList()),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 3, 14, 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: size + (shown.length - 1) * (size * 0.7),
                  height: size,
                  child: Stack(
                    children: [
                      for (final (i, p) in shown.indexed)
                        Positioned(
                          left: i * size * 0.7,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: context.colors.surface, width: 1.2),
                            ),
                            child: UserAvatar(user: p.user, size: size),
                          ),
                        ),
                    ],
                  ),
                ),
                if (rest > 0) ...[
                  const SizedBox(width: 4),
                  Text('+$rest', style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactionChoice extends StatelessWidget {
  const _ReactionChoice({required this.emoji, required this.selected, required this.onTap});

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    customBorder: const CircleBorder(),
    child: Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? context.palette.accent : null),
      child: Text(emoji, style: const TextStyle(fontSize: 26)),
    ),
  );
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    // Depende da língua (reconstrói quando muda).
    context.translations;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Pill(label: ChatFormat.day(date)),
    );
  }
}

/// A prenda do grupo, sempre à vista: é dela que se fala.
class _GiftBanner extends StatelessWidget {
  const _GiftBanner({required this.group});

  final GiftGroup group;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final status = g.purchasedAt != null
        ? context.tr(Keys.chatBannerPurchased)
        : context.tr(Keys.chatBannerProgress, {
            'collected': context.tr(Keys.chatGiftCollected, {
              'confirmed': Fmt.money(g.confirmedAmount),
              'target': Fmt.money(g.targetAmount),
            }),
            'people': context.trPlural(Keys.commonPeople, g.members.length),
          });
    return Material(
      color: context.palette.accent,
      child: InkWell(
        onTap: () => context.push('/groups/${g.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Icon(LucideIcons.gift, size: 20, color: context.palette.accentForeground),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.giftDescription.isNotEmpty ? g.giftDescription : g.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall?.copyWith(color: context.palette.accentForeground),
                    ),
                    Text(
                      context.tr(Keys.chatBannerFor, {'name': g.celebrantName, 'status': status}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(
                        color: context.palette.accentForeground.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 18, color: context.palette.accentForeground),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.conversation, required this.group});

  final Conversation? conversation;
  final GiftGroup? group;

  @override
  Widget build(BuildContext context) {
    final isGroup = conversation?.isGroup ?? false;
    return Center(
      child: SingleChildScrollView(
        child: EmptyState(
          icon: isGroup ? LucideIcons.messagesSquare : LucideIcons.hand,
          title: isGroup ? context.tr(Keys.chatEmptyGroupTitle) : context.tr(Keys.chatSayHello),
          message: isGroup
              ? group == null
                    ? context.tr(Keys.chatEmptyGroupMessage)
                    : context.tr(Keys.chatEmptyGroupMessageFor, {'name': group!.celebrantName})
              : context.tr(Keys.chatEmptyDirectMessage),
        ),
      ),
    );
  }
}

/// Imagem, GIF ou sticker em ecrã inteiro, com zoom.
class _MediaViewer extends StatelessWidget {
  const _MediaViewer({required this.message, this.onSaveSticker});

  final ChatMessage message;
  final Future<void> Function()? onSaveSticker;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(message.senderName, style: AppTheme.display(context, size: 18, color: Colors.white)),
        actions: [
          if (onSaveSticker != null)
            IconButton(
              tooltip: context.tr(Keys.chatActionSaveSticker),
              onPressed: () => runGuarded(context, onSaveSticker!, success: context.tr(Keys.chatStickerSaved)),
              icon: const Icon(LucideIcons.sticker),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: ChatImage(url: message.mediaUrl, bytes: message.localBytes, fit: BoxFit.contain),
              ),
            ),
          ),
          if (message.body.trim().isNotEmpty && message.kind == MessageKind.image)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(message.body, style: const TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
        ],
      ),
    );
  }
}
