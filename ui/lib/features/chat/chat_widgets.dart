import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/chat_models.dart';

/// Cor estável para cada pessoa (nome no balão e avatar).
Color userColor(BuildContext context, String userId) {
  const hues = [350.0, 20.0, 40.0, 150.0, 190.0, 220.0, 265.0, 300.0];
  final hue = hues[userId.codeUnits.fold(0, (a, b) => a + b) % hues.length];
  final dark = Theme.of(context).brightness == Brightness.dark;
  return HSLColor.fromAHSL(1, hue, 0.55, dark ? 0.68 : 0.42).toColor();
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.size = 40});

  final ChatUser user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = userColor(context, user.userId);
    final photo = user.photoUrl;
    if (photo != null) {
      return ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: ChatImage(url: photo),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.18), context.palette.card),
        shape: BoxShape.circle,
      ),
      child: Text(
        user.initials,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * 0.36, color: color),
      ),
    );
  }
}

/// Avatar com a bolinha verde quando a pessoa está online.
class PresenceAvatar extends ConsumerWidget {
  const PresenceAvatar({super.key, required this.user, this.size = 40});

  final ChatUser user;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(userPresenceProvider(user.userId)).online;
    final dot = (size * 0.28).clamp(9.0, 16.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        UserAvatar(user: user, size: size),
        if (online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: context.palette.success,
                shape: BoxShape.circle,
                border: Border.all(color: context.palette.card, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

/// Três pontos a saltar ("está a escrever…").
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.color, this.size = 7});

  final Color? color;
  final double size;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.palette.mutedForeground;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) SizedBox(width: widget.size * 0.6),
            Builder(
              builder: (context) {
                // Cada ponto sobe e desce um pouco depois do anterior.
                final t = (_ctrl.value - i * 0.18) % 1.0;
                final lift = t < 0.4 ? math.sin(t / 0.4 * math.pi) : 0.0;
                return Transform.translate(
                  offset: Offset(0, -lift * widget.size * 0.6),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.45 + lift * 0.55),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Avatar de um grupo: a fotografia, ou o presente em gradiente (cinzento se já comprada).
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({super.key, this.photoUrl, this.size = 48, this.purchased = false});

  final String? photoUrl;
  final double size;
  final bool purchased;

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null) {
      return ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: ChatImage(url: photoUrl),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: purchased ? null : context.palette.brand,
        color: purchased ? context.palette.muted : null,
        shape: BoxShape.circle,
      ),
      child: Icon(
        LucideIcons.gift,
        color: purchased ? context.palette.mutedForeground : Colors.white,
        size: size * 0.46,
      ),
    );
  }
}

/// Avatar de uma conversa: a fotografia do grupo ou a da pessoa (ou as iniciais).
class ConversationAvatar extends StatelessWidget {
  const ConversationAvatar({super.key, required this.conversation, this.size = 48});

  final Conversation conversation;
  final double size;

  @override
  Widget build(BuildContext context) {
    final other = conversation.otherUser;
    if (!conversation.isGroup && other != null) return PresenceAvatar(user: other, size: size);
    return GroupAvatar(photoUrl: conversation.photoUrl, size: size);
  }
}

/// Contador vermelho (não lidas, pedidos).
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.muted = false});

  final int count;

  /// Conversa silenciada: contador a cinzento.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? context.palette.mutedForeground.withValues(alpha: 0.55) : context.colors.primary,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: muted ? context.palette.card : context.colors.onPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Imagem de uma mensagem ou sticker: os bytes locais enquanto envia, senão
/// o URL (guardado em cache no dispositivo).
class ChatImage extends StatelessWidget {
  const ChatImage({super.key, this.url, this.bytes, this.fit = BoxFit.cover});

  final String? url;
  final Uint8List? bytes;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: context.palette.muted);
    if (bytes != null) {
      return Image.memory(bytes!, fit: fit, gaplessPlayback: true, errorBuilder: (_, _, _) => placeholder);
    }
    if (url == null) return placeholder;
    // Modo local: caminho de um ficheiro no dispositivo.
    if (!url!.startsWith('http')) {
      return Image.file(File(url!), fit: fit, errorBuilder: (_, _, _) => placeholder);
    }
    return CachedNetworkImage(
      imageUrl: url!,
      // A assinatura do URL muda todos os dias; a cache é pelo ficheiro.
      cacheKey: Uri.tryParse(url!)?.replace(query: '').toString(),
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => ColoredBox(
        color: context.palette.muted,
        child: Icon(LucideIcons.imageOff, color: context.palette.mutedForeground),
      ),
    );
  }
}

/// Imagem escolhida pela pessoa, já reduzida, com as dimensões.
typedef PickedImage = ({Uint8List bytes, int? width, int? height});

Future<PickedImage?> pickChatImage(ImageSource source, {double maxSide = 1600}) async {
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: maxSide,
    maxHeight: maxSide,
    imageQuality: 85,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  int? width;
  int? height;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    width = frame.image.width;
    height = frame.image.height;
    frame.image.dispose();
    codec.dispose();
  } catch (_) {
    // Sem dimensões a mensagem usa uma proporção quadrada.
  }
  return (bytes: bytes, width: width, height: height);
}

/// Fotografia (de perfil ou do grupo) em ecrã inteiro, com zoom. Tocar
/// na fotografia pequena abre-a; [heroTag] anima a passagem entre as duas.
Future<void> openPhotoViewer(BuildContext context, {required String url, required String title, Object? heroTag}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(title, style: const TextStyle(color: Colors.white)),
        ),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Hero(
              tag: heroTag ?? url,
              child: ChatImage(url: url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Envolve um avatar: se houver fotografia, tocar abre-a em ecrã inteiro.
class ZoomablePhoto extends StatelessWidget {
  const ZoomablePhoto({super.key, required this.url, required this.title, required this.child});

  final String? url;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final photo = url;
    if (photo == null) return child;
    // A mesma fotografia vem com outra assinatura todos os dias: a etiqueta é o ficheiro.
    final tag = 'photo:${Uri.tryParse(photo)?.path ?? photo}';
    return Semantics(
      button: true,
      label: 'Ver fotografia de $title',
      child: GestureDetector(
        onTap: () => openPhotoViewer(context, url: photo, title: title, heroTag: tag),
        child: Hero(tag: tag, child: child),
      ),
    );
  }
}
