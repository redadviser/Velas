import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/birthday_utils.dart';
import '../../data/models/chat_models.dart';
import 'chat_widgets.dart';

/// Uma mensagem na conversa. As mensagens seguidas da mesma pessoa formam um
/// bloco: o nome aparece na primeira e o avatar na última.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.myId,
    required this.isGroup,
    this.firstInRun = true,
    this.lastInRun = true,
    this.seen = false,
    this.onLongPress,
    this.onOpenMedia,
    this.onReact,
    this.onRetry,
    this.onTapReply,
    this.onTapSender,
  });

  final ChatMessage message;
  final String myId;
  final bool isGroup;
  final bool firstInRun;
  final bool lastInRun;

  /// Conversa privada: a outra pessoa já leu (mostra ✓✓).
  final bool seen;
  final VoidCallback? onLongPress;
  final VoidCallback? onOpenMedia;
  final ValueChanged<String>? onReact;
  final VoidCallback? onRetry;
  final VoidCallback? onTapReply;

  /// Tocar no avatar ou no nome de quem enviou (abre o perfil).
  final VoidCallback? onTapSender;

  bool get _mine => message.senderId == myId;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final mine = _mine;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.76;
    final showAvatar = isGroup && !mine;

    final content = GestureDetector(
      onLongPress: m.deleted || m.state == SendState.sending ? null : onLongPress,
      child: switch (m) {
        _ when m.deleted => _TextBubble(message: m, mine: mine, lastInRun: lastInRun, seen: seen),
        _ when m.isBigEmoji => _BigEmoji(message: m, mine: mine, seen: seen),
        _ when m.kind == MessageKind.sticker => _Sticker(message: m, mine: mine, seen: seen, onTap: onOpenMedia),
        _ when m.kind == MessageKind.image || m.kind == MessageKind.gif => _MediaBubble(
          message: m,
          mine: mine,
          lastInRun: lastInRun,
          seen: seen,
          onTap: onOpenMedia,
          onTapReply: onTapReply,
        ),
        _ => _TextBubble(message: m, mine: mine, lastInRun: lastInRun, seen: seen, onTapReply: onTapReply),
      },
    );

    return Padding(
      padding: EdgeInsets.only(top: firstInRun ? 10 : 2, left: 12, right: 12),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showAvatar) ...[
            SizedBox(
              width: 30,
              child: lastInRun && m.senderId != null
                  ? GestureDetector(
                      onTap: onTapSender,
                      child: UserAvatar(
                        user: ChatUser(userId: m.senderId!, name: m.senderName, photoUrl: m.senderPhotoUrl),
                        size: 30,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 6),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (isGroup && !mine && firstInRun)
                  GestureDetector(
                    onTap: onTapSender,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 2),
                      child: Text(
                        m.senderId == null ? 'Conta eliminada' : m.senderName,
                        style: context.text.labelMedium?.copyWith(
                          color: m.senderId == null ? context.palette.mutedForeground : userColor(context, m.senderId!),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                content,
                if (m.reactions.isNotEmpty) _Reactions(message: m, myId: myId, onReact: onReact),
                if (m.state == SendState.failed)
                  TextButton.icon(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: context.colors.error,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(LucideIcons.circleAlert, size: 14),
                    label: const Text('Não enviada · tocar para tentar de novo'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

BorderRadius _bubbleRadius(bool mine, bool lastInRun) {
  const r = Radius.circular(18);
  const tail = Radius.circular(5);
  return BorderRadius.only(
    topLeft: r,
    topRight: r,
    bottomLeft: !mine && lastInRun ? tail : r,
    bottomRight: mine && lastInRun ? tail : r,
  );
}

(Color, Color) _bubbleColors(BuildContext context, bool mine) =>
    mine ? (context.colors.primary, context.colors.onPrimary) : (context.palette.muted, context.colors.onSurface);

/// Hora e estado (a enviar, enviada, vista).
class _Meta extends StatelessWidget {
  const _Meta({required this.message, required this.mine, required this.seen, required this.color});

  final ChatMessage message;
  final bool mine;
  final bool seen;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 11, color: color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(Fmt.time(message.createdAt), style: style),
        if (mine && !message.deleted) ...[
          const SizedBox(width: 3),
          Icon(
            switch (message.state) {
              SendState.sending => LucideIcons.clock3,
              SendState.failed => LucideIcons.circleAlert,
              SendState.sent => seen ? LucideIcons.checkCheck : LucideIcons.check,
            },
            size: 13,
            color: message.state == SendState.failed ? context.colors.error : color,
          ),
        ],
      ],
    );
  }
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.reply, required this.mine, this.onTap});

  final MessageReply reply;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = mine ? context.colors.onPrimary : context.colors.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: fg.withValues(alpha: 0.6), width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              reply.senderName.isEmpty ? 'Mensagem' : reply.senderName,
              style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
            ),
            Text(
              ChatMessage.previewOf(reply.kind, reply.body, deleted: reply.deleted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({
    required this.message,
    required this.mine,
    required this.lastInRun,
    required this.seen,
    this.onTapReply,
  });

  final ChatMessage message;
  final bool mine;
  final bool lastInRun;
  final bool seen;
  final VoidCallback? onTapReply;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _bubbleColors(context, mine);
    final deleted = message.deleted;
    final textStyle = context.text.bodyLarge?.copyWith(
      color: deleted ? fg.withValues(alpha: 0.7) : fg,
      fontStyle: deleted ? FontStyle.italic : null,
      height: 1.3,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        color: deleted ? bg.withValues(alpha: 0.55) : bg,
        borderRadius: _bubbleRadius(mine, lastInRun),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.reply != null && !deleted) _ReplyQuote(reply: message.reply!, mine: mine, onTap: onTapReply),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text(deleted ? 'Mensagem apagada' : message.body, style: textStyle),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: _Meta(message: message, mine: mine, seen: seen, color: fg.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BigEmoji extends StatelessWidget {
  const _BigEmoji({required this.message, required this.mine, required this.seen});

  final ChatMessage message;
  final bool mine;
  final bool seen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(message.body.trim(), style: const TextStyle(fontSize: 46, height: 1.15)),
      _Meta(message: message, mine: mine, seen: seen, color: context.palette.mutedForeground),
    ],
  );
}

class _Sticker extends StatelessWidget {
  const _Sticker({required this.message, required this.mine, required this.seen, this.onTap});

  final ChatMessage message;
  final bool mine;
  final bool seen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = (message.aspectRatio ?? 1).clamp(0.5, 2.0);
    const side = 150.0;
    return Column(
      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: ratio >= 1 ? side : side * ratio,
            height: ratio >= 1 ? side / ratio : side,
            child: ChatImage(url: message.mediaUrl, bytes: message.localBytes, fit: BoxFit.contain),
          ),
        ),
        _Meta(message: message, mine: mine, seen: seen, color: context.palette.mutedForeground),
      ],
    );
  }
}

class _MediaBubble extends StatelessWidget {
  const _MediaBubble({
    required this.message,
    required this.mine,
    required this.lastInRun,
    required this.seen,
    this.onTap,
    this.onTapReply,
  });

  final ChatMessage message;
  final bool mine;
  final bool lastInRun;
  final bool seen;
  final VoidCallback? onTap;
  final VoidCallback? onTapReply;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _bubbleColors(context, mine);
    final m = message;
    final ratio = (m.aspectRatio ?? 1).clamp(0.6, 1.8);
    final width = MediaQuery.sizeOf(context).width * 0.62;
    final caption = m.body.trim();

    final image = ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: SizedBox(
        width: width,
        height: width / ratio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ChatImage(url: m.mediaUrl, bytes: m.localBytes),
            if (m.state == SendState.sending && m.localBytes != null)
              const ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
              ),
            if (m.kind == MessageKind.gif) const Positioned(left: 8, top: 8, child: _GifTag()),
            if (caption.isEmpty)
              Positioned(
                right: 8,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(99)),
                  child: _Meta(message: m, mine: mine, seen: seen, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: bg, borderRadius: _bubbleRadius(mine, lastInRun)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.reply != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: SizedBox(
                width: width - 12,
                child: _ReplyQuote(reply: m.reply!, mine: mine, onTap: onTapReply),
              ),
            ),
          GestureDetector(onTap: onTap, child: image),
          if (caption.isNotEmpty)
            SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 6, 9, 3),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 8,
                  children: [
                    Text(caption, style: context.text.bodyLarge?.copyWith(color: fg, height: 1.3)),
                    _Meta(message: m, mine: mine, seen: seen, color: fg.withValues(alpha: 0.7)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GifTag extends StatelessWidget {
  const _GifTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(6)),
    child: const Text(
      'GIF',
      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );
}

class _Reactions extends StatelessWidget {
  const _Reactions({required this.message, required this.myId, this.onReact});

  final ChatMessage message;
  final String myId;
  final ValueChanged<String>? onReact;

  @override
  Widget build(BuildContext context) {
    final mine = message.reactionOf(myId);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final MapEntry(key: emoji, value: users) in message.reactionGroups.entries)
            Material(
              color: emoji == mine ? context.palette.accent : context.palette.card,
              shape: StadiumBorder(
                side: BorderSide(color: emoji == mine ? context.colors.primary : context.palette.border),
              ),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onReact == null ? null : () => onReact!(emoji),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  child: Text(
                    users.length > 1 ? '$emoji ${users.length}' : emoji,
                    style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
