import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/chat_providers.dart';
import '../../core/config/env.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../data/api/chat_socket.dart';

/// O link para pedir aniversários: quem o abre deixa o nome e a data, que
/// ficam à espera de serem aceites (ver backend/src/modules/birthday-requests).
typedef BirthdayRequestLink = ({String token, int answers, int pending, bool enabled, bool open});

BirthdayRequestLink _link(Object? res) {
  final j = (res as Map).cast<String, dynamic>();
  return (
    token: j['token'] as String,
    answers: (j['answers'] as num?)?.toInt() ?? 0,
    pending: (j['pending'] as num?)?.toInt() ?? 0,
    enabled: j['enabled'] as bool? ?? true,
    open: j['open'] as bool? ?? true,
  );
}

/// `null` sem servidor (modo local). Atualiza quando alguém responde.
final birthdayRequestProvider = FutureProvider.autoDispose<BirthdayRequestLink?>((ref) async {
  final api = ref.watch(apiClientProvider);
  if (api == null || ref.watch(currentUserProvider.select((u) => u?.id)) == null) return null;
  final sub = ref.watch(chatEventsProvider).listen((e) {
    if (e is DataChanged) ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);
  return _link(await api.get('/birthday-request'));
});

/// Uma resposta por confirmar.
typedef PendingAnswer = ({String id, String name, int day, int month, int? year});

final pendingAnswersProvider = FutureProvider.autoDispose<List<PendingAnswer>>((ref) async {
  final api = ref.watch(apiClientProvider);
  if (api == null) return const [];
  final sub = ref.watch(chatEventsProvider).listen((e) {
    if (e is DataChanged) ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);
  final rows = (await api.get('/birthday-request/answers')) as List;
  return [
    for (final r in rows.cast<Map>())
      (
        id: r['id'] as String,
        name: r['name'] as String,
        day: (r['birth_day'] as num).toInt(),
        month: (r['birth_month'] as num).toInt(),
        year: (r['birth_year'] as num?)?.toInt(),
      ),
  ];
});

class BirthdayRequestLinks {
  const BirthdayRequestLinks._();

  static String shareLink(String token) {
    final base = (Env.inviteBaseUrl.isNotEmpty ? Env.inviteBaseUrl : Env.apiUrl).replaceFirst(RegExp(r'/+$'), '');
    return '$base/b/$token';
  }

  static String shareMessage(String token) =>
      'Estou a juntar os aniversários de quem gosto para nunca me esquecer 🎂 '
      'Deixa aqui o teu, demora 10 segundos: ${shareLink(token)}';
}

/// Partilhar o link (WhatsApp, etc.). Desligado ou expirado, troca primeiro por um novo.
Future<void> shareBirthdayRequest(BuildContext context, WidgetRef ref) async {
  BirthdayRequestLink? link;
  final ok = await runGuarded(context, () async {
    link = await ref.read(birthdayRequestProvider.future);
    if (link != null && !link!.open) link = _link(await ref.read(apiClientProvider)!.post('/birthday-request/reset'));
  });
  if (!ok || link == null) return;
  ref.invalidate(birthdayRequestProvider);
  await SharePlus.instance.share(ShareParams(text: BirthdayRequestLinks.shareMessage(link!.token)));
}

/// Trocar de link (o antigo deixa de funcionar) ou desligá-lo/voltar a ligá-lo.
Future<void> _manage(BuildContext context, WidgetRef ref, String action) async {
  final api = ref.read(apiClientProvider)!;
  await runGuarded(
    context,
    () => switch (action) {
      'reset' => api.post('/birthday-request/reset'),
      'off' => api.patch('/birthday-request', {'enabled': false}),
      _ => api.patch('/birthday-request', {'enabled': true}),
    },
    success: switch (action) {
      'reset' => 'Link novo criado. O antigo deixou de funcionar.',
      'off' => 'Link desligado: ninguém consegue responder.',
      _ => 'Link ligado outra vez.',
    },
  );
  ref.invalidate(birthdayRequestProvider);
}

/// "Não sabes a data? Pede-a." Só com servidor.
class BirthdayRequestCard extends ConsumerWidget {
  const BirthdayRequestCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(apiClientProvider) == null) return const SizedBox.shrink();
    final link = ref.watch(birthdayRequestProvider).value;
    final fg = context.palette.accentForeground;
    final pending = link?.pending ?? 0;
    final subtitle = link != null && !link.open
        ? (link.enabled ? 'O link expirou. Partilha para criar um novo.' : 'O link está desligado: ninguém consegue responder.')
        : pending > 0
        ? '${pending == 1 ? '1 resposta à espera' : '$pending respostas à espera'} de confirmação. Toca para ver.'
        : (link?.answers ?? 0) > 0
        ? '${link!.answers == 1 ? '1 pessoa já deixou' : '${link.answers} pessoas já deixaram'} a data pelo teu link.'
        : 'Envia um link ao grupo da família ou dos amigos: cada um deixa a sua data e tu confirmas.';
    return AppCard(
      color: context.palette.accent,
      onTap: pending > 0 ? () => context.push('/people/requests') : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 0, 12),
      child: Row(
        children: [
          Icon(pending > 0 ? LucideIcons.inbox : LucideIcons.link, color: fg, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Não sabes a data? Pede-a', style: context.text.titleSmall?.copyWith(color: fg)),
                Text(subtitle, style: context.text.bodySmall?.copyWith(color: fg.withValues(alpha: 0.85))),
              ],
            ),
          ),
          TextButton(onPressed: () => shareBirthdayRequest(context, ref), child: const Text('Partilhar')),
          if (link != null)
            PopupMenuButton<String>(
              tooltip: 'Gerir o link',
              icon: Icon(LucideIcons.ellipsisVertical, size: 18, color: fg),
              onSelected: (a) => _manage(context, ref, a),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'reset', child: Text('Trocar link')),
                if (link.enabled)
                  const PopupMenuItem(value: 'off', child: Text('Desligar link'))
                else
                  const PopupMenuItem(value: 'on', child: Text('Ligar link')),
              ],
            ),
        ],
      ),
    );
  }
}
