import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/cards_providers.dart';
import '../../core/chat_providers.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/card_models.dart';
import '../../data/models/chat_models.dart';
import '../auth/auth_widgets.dart';
import '../chat/chat_widgets.dart';

final _cardProvider = FutureProvider.autoDispose.family<GreetingCard, String>((ref, token) {
  return ref.watch(cardsRepositoryProvider)!.preview(token);
});

/// Cartão de parabéns aberto a partir do link, mesmo sem conta: a mensagem
/// lê-se logo e, para responder, a pessoa entra (ou cria conta) e guarda o
/// cartão, o que abre a conversa com quem o enviou.
class CardScreen extends ConsumerStatefulWidget {
  const CardScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends ConsumerState<CardScreen> {
  bool _claiming = false;
  bool _markedOpened = false;

  void _close() => context.canPop() ? context.pop() : context.go('/home');

  /// Quem enviou também pode abrir o link: isso não conta como aberto.
  void _markOpened(GreetingCard card) {
    if (_markedOpened || card.senderId == ref.read(currentUserProvider)?.id) return;
    _markedOpened = true;
    ref.read(cardsRepositoryProvider)!.markOpened(widget.token).catchError((_) {});
  }

  Future<void> _reply(GreetingCard card) async {
    setState(() => _claiming = true);
    final router = GoRouter.of(context);
    String? conversationId;
    final ok = await runGuarded(context, () async {
      final claimed = await ref.read(cardsRepositoryProvider)!.claim(widget.token);
      ref.invalidate(friendsProvider);
      ref.invalidate(wallProvider);
      conversationId = await ref.read(conversationsProvider.notifier).openDirect(claimed.senderId);
    });
    if (!mounted) return;
    setState(() => _claiming = false);
    if (ok && conversationId != null) router.pushReplacement('/chats/$conversationId');
  }

  @override
  Widget build(BuildContext context) {
    final card = ref.watch(_cardProvider(widget.token));
    ref.listen(_cardProvider(widget.token), (_, next) => next.whenData(_markOpened));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(LucideIcons.x), onPressed: _close),
      ),
      body: SafeArea(
        child: card.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(_cardProvider(widget.token))),
          data: (c) => _CardBody(card: c, actions: _actions(c)),
        ),
      ),
    );
  }

  List<Widget> _actions(GreetingCard card) {
    final me = ref.watch(currentUserProvider);
    final muted = context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground);
    final reply = 'Responder a ${card.senderFirstName}';
    if (me == null) {
      return [
        Text(
          'Cria conta para agradecer a ${card.senderFirstName}, guardar a mensagem e não te esqueceres '
          'dos aniversários de quem gostas.',
          textAlign: TextAlign.center,
          style: muted,
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => context.go('/register'), child: Text(reply)),
        const SizedBox(height: 8),
        TextButton(onPressed: () => context.go('/login'), child: const Text('Já tenho conta')),
      ];
    }
    if (card.senderId == me.id) {
      return [
        Text('Este é o cartão que enviaste.', textAlign: TextAlign.center, style: muted),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: _close, child: const Text('Fechar')),
      ];
    }
    return [
      Text(
        'A mensagem fica guardada na tua conversa com ${card.senderFirstName}.',
        textAlign: TextAlign.center,
        style: muted,
      ),
      const SizedBox(height: 16),
      LoadingButton(label: reply, icon: LucideIcons.messageCircle, loading: _claiming, onPressed: () => _reply(card)),
      const SizedBox(height: 8),
      TextButton(onPressed: _close, child: const Text('Agora não')),
    ];
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.card, required this.actions});

  final GreetingCard card;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.mutedForeground;
    final sender = ChatUser(userId: card.senderId, name: card.senderName, photoUrl: card.senderPhotoUrl);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
            child: UserAvatar(user: sender, size: 72),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${card.senderName} deixou-te uma mensagem',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 6),
        Text('Parabéns, ${card.recipientName}! 🎉', textAlign: TextAlign.center, style: AppTheme.display(context, size: 28)),
        const SizedBox(height: 20),
        AppCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                card.body,
                style: AppTheme.display(context, size: 18).copyWith(fontWeight: FontWeight.w400, height: 1.55),
              ),
              const SizedBox(height: 12),
              Text(
                '— ${card.senderName}',
                textAlign: TextAlign.right,
                style: context.text.bodyMedium?.copyWith(color: muted, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        ...actions,
      ],
    );
  }
}
