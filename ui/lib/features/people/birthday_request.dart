import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/chat_providers.dart';
import '../../core/config/env.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../data/api/chat_socket.dart';

/// O link para pedir aniversários: quem o abre deixa o nome e a data, que
/// entram na minha lista (ver backend/src/modules/birthday-requests).
typedef BirthdayRequestLink = ({String token, int answers});

/// `null` sem servidor (modo local). Atualiza quando alguém responde.
final birthdayRequestProvider = FutureProvider.autoDispose<BirthdayRequestLink?>((ref) async {
  final api = ref.watch(apiClientProvider);
  if (api == null || ref.watch(currentUserProvider.select((u) => u?.id)) == null) return null;
  final sub = ref.watch(chatEventsProvider).listen((e) {
    if (e is DataChanged) ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);
  final res = ((await api.get('/birthday-request')) as Map).cast<String, dynamic>();
  return (token: res['token'] as String, answers: (res['answers'] as num).toInt());
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

/// Partilhar o link (WhatsApp, etc.).
Future<void> shareBirthdayRequest(BuildContext context, WidgetRef ref) async {
  BirthdayRequestLink? link;
  final ok = await runGuarded(context, () async => link = await ref.read(birthdayRequestProvider.future));
  if (!ok || link == null) return;
  await SharePlus.instance.share(ShareParams(text: BirthdayRequestLinks.shareMessage(link!.token)));
}

/// "Não sabes a data? Pede-a." Só com servidor.
class BirthdayRequestCard extends ConsumerWidget {
  const BirthdayRequestCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(apiClientProvider) == null) return const SizedBox.shrink();
    final answers = ref.watch(birthdayRequestProvider).value?.answers ?? 0;
    final fg = context.palette.accentForeground;
    return AppCard(
      color: context.palette.accent,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(LucideIcons.link, color: fg, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Não sabes a data? Pede-a', style: context.text.titleSmall?.copyWith(color: fg)),
                Text(
                  answers > 0
                      ? '${answers == 1 ? '1 pessoa já deixou' : '$answers pessoas já deixaram'} a data pelo teu link.'
                      : 'Envia um link ao grupo da família ou dos amigos: cada um deixa a sua data e ela aparece aqui.',
                  style: context.text.bodySmall?.copyWith(color: fg.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          TextButton(onPressed: () => shareBirthdayRequest(context, ref), child: const Text('Partilhar')),
        ],
      ),
    );
  }
}
