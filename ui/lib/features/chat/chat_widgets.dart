import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
      return ClipOval(child: SizedBox.square(dimension: size, child: ChatImage(url: photo)));
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

/// Avatar de uma conversa: a prenda (grupo) ou as iniciais da pessoa.
class ConversationAvatar extends StatelessWidget {
  const ConversationAvatar({super.key, required this.conversation, this.size = 48});

  final Conversation conversation;
  final double size;

  @override
  Widget build(BuildContext context) {
    final other = conversation.otherUser;
    if (!conversation.isGroup && other != null) return UserAvatar(user: other, size: size);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
      child: Icon(LucideIcons.gift, color: Colors.white, size: size * 0.46),
    );
  }
}

/// Contador vermelho (não lidas, pedidos).
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: context.colors.primary, borderRadius: BorderRadius.circular(99)),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(color: context.colors.onPrimary, fontSize: 11, fontWeight: FontWeight.w700),
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
