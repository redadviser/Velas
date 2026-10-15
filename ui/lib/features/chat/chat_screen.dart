import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../data/models/group_models.dart';
import 'chat_widgets.dart';
import 'composer.dart';
import 'media_panel.dart';
import 'message_bubble.dart';

const quickReactions = ['❤️', '😂', '😮', '😢', '🎉', '👍'];

/// Mensagens seguidas da mesma pessoa com menos disto entre si ficam no mesmo bloco.
const _runGap = Duration(minutes: 5);

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
                        selected: m.reactionOf(ref.read(currentUserProvider)!.id) == e,
                        onTap: () => Navigator.pop(ctx, 'react:$e'),
                      ),
                    IconButton.filledTonal(
                      tooltip: 'Mais emojis',
                      onPressed: () => Navigator.pop(ctx, 'react-more'),
                      icon: const Icon(LucideIcons.plus, size: 20),
                    ),
                  ],
                ),
              ),
            if (m.state == SendState.sent)
              ListTile(
                leading: const Icon(LucideIcons.reply),
                title: const Text('Responder'),
                onTap: () => Navigator.pop(ctx, 'reply'),
              ),
            if (m.kind == MessageKind.text)
              ListTile(
                leading: const Icon(LucideIcons.copy),
                title: const Text('Copiar texto'),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
            if (canSave)
              ListTile(
                leading: const Icon(LucideIcons.sticker),
                title: const Text('Guardar nos meus stickers'),
                onTap: () => Navigator.pop(ctx, 'sticker'),
              ),
            if (m.state == SendState.failed) ...[
              ListTile(
                leading: const Icon(LucideIcons.refreshCw),
                title: const Text('Tentar enviar de novo'),
                onTap: () => Navigator.pop(ctx, 'retry'),
              ),
              ListTile(
                leading: const Icon(LucideIcons.x),
                title: const Text('Descartar'),
                onTap: () => Navigator.pop(ctx, 'discard'),
              ),
            ],
            if (mine && m.state == SendState.sent)
              ListTile(
                leading: Icon(LucideIcons.trash2, color: ctx.colors.error),
                title: Text('Apagar para todos', style: TextStyle(color: ctx.colors.error)),
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
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.body));
        if (mounted) showMessage(context, 'Texto copiado.');
      case 'sticker':
        await runGuarded(context, () => ref.read(stickersProvider.notifier).saveFromMessage(m), success: 'Guardado nos teus stickers.');
      case 'retry':
        await _chat.retry(m).catchError((_) {});
      case 'discard':
        _chat.discard(m);
      case 'delete':
        final ok = await confirmDialog(
          context,
          title: 'Apagar mensagem?',
          message: 'Fica "Mensagem apagada" para todos na conversa.',
          confirm: 'Apagar',
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
        child: EmojiPicker(
          onEmojiSelected: (_, e) => Navigator.pop(ctx, e.emoji),
          config: emojiConfig(ctx),
        ),
      ),
    ),
  );

  void _openMedia(ChatMessage m) {
    if (m.mediaUrl == null && m.localBytes == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _MediaViewer(
          message: m,
          onSaveSticker: m.state == SendState.sent ? () => ref.read(stickersProvider.notifier).saveFromMessage(m) : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider(widget.conversationId));
    final me = ref.watch(currentUserProvider)?.id ?? '';
    final summary =
        state.conversation ??
        ref.watch(conversationsProvider).value?.where((c) => c.id == widget.conversationId).firstOrNull;
    final groupId = summary?.groupId;
    final group = groupId == null
        ? null
        : ref.watch(groupsProvider).value?.where((g) => g.id == groupId).firstOrNull;
    final other = summary?.otherUser;
    final friends = ref.watch(friendsProvider).value;
    // Deixaram de ser amigos: a conversa fica, mas não se escreve.
    final blocked = summary != null && !summary.isGroup && other != null && friends != null && !friends.isFriend(other.userId);

    final otherRead = !(summary?.isGroup ?? true) && other != null
        ? state.conversation?.participants.where((p) => p.user.userId == other.userId).firstOrNull?.lastReadAt
        : null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: summary == null
            ? null
            : InkWell(
                onTap: groupId == null ? null : () => context.push('/groups/$groupId'),
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  children: [
                    ConversationAvatar(conversation: summary, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(summary.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                          Text(
                            _subtitle(summary, state, me),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall?.copyWith(
                              color: state.typing.isEmpty ? context.palette.mutedForeground : context.colors.primary,
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
              tooltip: 'Ver a prenda',
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
                : state.messages.isEmpty
                ? _EmptyChat(conversation: summary, group: group)
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.only(bottom: 10),
                    itemCount: state.messages.length + (state.hasMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      final list = state.messages;
                      if (i == list.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                        );
                      }
                      final m = list[i];
                      final older = i + 1 < list.length ? list[i + 1] : null;
                      final newer = i > 0 ? list[i - 1] : null;
                      final newDay = older == null ? !state.hasMore : !_sameDay(older.createdAt, m.createdAt);
                      final mine = m.senderId == me;
                      return Column(
                        children: [
                          if (newDay) _DaySeparator(date: m.createdAt),
                          MessageBubble(
                            key: ValueKey(m.id),
                            message: m,
                            myId: me,
                            isGroup: summary?.isGroup ?? false,
                            firstInRun: newDay || !_sameRun(older, m),
                            lastInRun: !_sameRun(m, newer),
                            seen: mine && otherRead != null && !otherRead.isBefore(m.createdAt),
                            onLongPress: () => _actions(m, mine: mine),
                            onOpenMedia: () => _openMedia(m),
                            onReact: m.state == SendState.sent
                                ? (e) => runGuarded(context, () => _chat.react(m, e))
                                : null,
                            onRetry: () => _chat.retry(m).catchError((_) {}),
                          ),
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
                  'Já não são amigos. Podes ler a conversa, mas não enviar mensagens.',
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

  String _subtitle(Conversation c, ChatState state, String me) {
    final typing = state.typing.values.map((n) => n.split(' ').first).toList();
    if (typing.length == 1) return '${typing.first} está a escrever…';
    if (typing.length > 1) return '${typing.join(', ')} estão a escrever…';
    if (!c.isGroup) return c.otherUser?.username.isNotEmpty ?? false ? '@${c.otherUser!.username}' : 'Conversa privada';
    final names = state.conversation?.participants.where((p) => p.user.userId != me).map((p) => p.user.firstName).toList();
    if (names == null || names.isEmpty) return c.celebrantName == null ? 'Grupo' : 'Prenda para ${c.celebrantName}';
    return names.length <= 3 ? 'Tu, ${names.join(', ')}' : 'Tu, ${names.take(3).join(', ')} e mais ${names.length - 3}';
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Pill(label: Fmt.chatDay(date)),
  );
}

/// A prenda do grupo, sempre à vista: é dela que se fala.
class _GiftBanner extends StatelessWidget {
  const _GiftBanner({required this.group});

  final GiftGroup group;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final status = g.purchasedAt != null
        ? 'Comprada 🎉'
        : '${Fmt.money(g.confirmedAmount)} de ${Fmt.money(g.targetAmount)} · ${g.members.length} pessoas';
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
                      'Para ${g.celebrantName} · $status',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(color: context.palette.accentForeground.withValues(alpha: 0.8)),
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
          title: isGroup ? 'Combinem a prenda aqui' : 'Diz olá 👋',
          message: isGroup
              ? 'Partilhem ideias, links e fotografias da prenda${group == null ? '' : ' para ${group!.celebrantName}'}.'
              : 'Esta conversa é só entre vocês os dois.',
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
        title: Text(
          message.senderName,
          style: AppTheme.display(context, size: 18, color: Colors.white),
        ),
        actions: [
          if (onSaveSticker != null)
            IconButton(
              tooltip: 'Guardar nos meus stickers',
              onPressed: () => runGuarded(context, onSaveSticker!, success: 'Guardado nos teus stickers.'),
              icon: const Icon(LucideIcons.sticker),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(child: ChatImage(url: message.mediaUrl, bytes: message.localBytes, fit: BoxFit.contain)),
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
