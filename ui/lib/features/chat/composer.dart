import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/errors.dart';
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import 'chat_widgets.dart';
import 'media_panel.dart';

/// Caixa de escrita: texto (com emojis), fotografias, GIFs e stickers.
class Composer extends ConsumerStatefulWidget {
  const Composer({super.key, required this.conversationId, this.replyTo, required this.onCancelReply});

  final String conversationId;
  final ChatMessage? replyTo;
  final VoidCallback onCancelReply;

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  MediaTab? _panel;

  ChatController get _chat => ref.read(chatProvider(widget.conversationId).notifier);

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _focus.addListener(() {
      if (_focus.hasFocus && _panel != null) setState(() => _panel = null);
    });
  }

  @override
  void didUpdateWidget(Composer old) {
    super.didUpdateWidget(old);
    if (widget.replyTo != null && old.replyTo?.id != widget.replyTo!.id) _focus.requestFocus();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Os erros de rede ficam visíveis na própria mensagem ("tocar para tentar de novo").
  Future<void> _run(Future<void> Function() send) async {
    widget.onCancelReply();
    try {
      await send();
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {}
  }

  void _sendText() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final reply = widget.replyTo;
    _text.clear();
    _run(() => _chat.sendText(text, replyTo: reply));
  }

  Future<void> _attach() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.images),
              title: const Text('Galeria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: const Text('Câmara'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    PickedImage? picked;
    try {
      picked = await pickChatImage(source);
    } catch (_) {
      if (mounted) showMessage(context, 'Não foi possível aceder às fotografias. Verifica as permissões.');
      return;
    }
    if (picked == null) return;
    // O que estiver escrito vai como legenda.
    final caption = _text.text.trim();
    final reply = widget.replyTo;
    _text.clear();
    final p = picked;
    _run(() => _chat.sendImage(p.bytes, width: p.width, height: p.height, caption: caption, replyTo: reply));
  }

  void _togglePanel(MediaTab tab) {
    if (_panel == tab) {
      setState(() => _panel = null);
      _focus.requestFocus();
    } else {
      _focus.unfocus();
      setState(() => _panel = tab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reply = widget.replyTo;
    final hasText = _text.text.trim().isNotEmpty;
    final muted = context.palette.mutedForeground;

    return Material(
      color: context.palette.card,
      child: SafeArea(
        top: false,
        bottom: _panel == null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(height: 1, color: context.palette.border),
            if (reply != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                child: Row(
                  children: [
                    Container(width: 3, height: 34, color: context.colors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'A responder a ${reply.senderName}',
                            style: context.text.labelMedium?.copyWith(color: context.colors.primary, fontWeight: FontWeight.w700),
                          ),
                          Text(reply.preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancelar resposta',
                      onPressed: widget.onCancelReply,
                      icon: Icon(LucideIcons.x, size: 18, color: muted),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Enviar fotografia',
                    onPressed: _attach,
                    icon: Icon(LucideIcons.imagePlus, color: muted),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => _chat.typing(),
                      decoration: InputDecoration(
                        hintText: 'Mensagem',
                        counterText: '',
                        isDense: true,
                        contentPadding: const EdgeInsets.fromLTRB(16, 11, 4, 11),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: context.palette.muted,
                        suffixIcon: IconButton(
                          tooltip: 'Emojis',
                          onPressed: () => _togglePanel(MediaTab.emoji),
                          icon: Icon(
                            _panel == MediaTab.emoji ? LucideIcons.keyboard : LucideIcons.smile,
                            size: 20,
                            color: _panel == MediaTab.emoji ? context.colors.primary : muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (hasText)
                    IconButton.filled(
                      tooltip: 'Enviar',
                      onPressed: _sendText,
                      icon: const Icon(LucideIcons.sendHorizontal, size: 20),
                    )
                  else
                    IconButton(
                      tooltip: 'GIFs e stickers',
                      // Com o painel nos stickers, volta a tocar fecha-o; senão abre nos GIFs.
                      onPressed: () => _togglePanel(_panel == MediaTab.stickers ? MediaTab.stickers : MediaTab.gifs),
                      icon: Icon(
                        LucideIcons.sticker,
                        color: _panel == MediaTab.gifs || _panel == MediaTab.stickers ? context.colors.primary : muted,
                      ),
                    ),
                ],
              ),
            ),
            if (_panel != null)
              SafeArea(
                top: false,
                child: MediaPanel(
                  initialTab: _panel!,
                  textController: _text,
                  onGif: (g, {required asSticker}) {
                    final reply = widget.replyTo;
                    setState(() => _panel = null);
                    _run(() => _chat.sendGif(g, asSticker: asSticker, replyTo: reply));
                  },
                  onSticker: (s) {
                    final reply = widget.replyTo;
                    setState(() => _panel = null);
                    _run(() => _chat.sendSticker(s, replyTo: reply));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
