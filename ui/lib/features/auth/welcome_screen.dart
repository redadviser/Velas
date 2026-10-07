import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import 'auth_widgets.dart';
import 'register_screen.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final google = ref.watch(authRepositoryProvider).supportsGoogle;
    final media = MediaQuery.of(context);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              padding: EdgeInsets.fromLTRB(24, media.padding.top + 20, 24, 28),
              child: LayoutBuilder(
                builder: (context, c) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrandMark(size: 36, onGradient: true),
                    const Spacer(),
                    Text(
                      'Nunca mais te esqueças de quem importa.',
                      style: AppTheme.display(context, size: 32, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Todos os aniversários num só lugar, lembretes no momento certo e prendas tratadas a tempo.',
                      style: context.text.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                      ),
                    ),
                    if (c.maxHeight > 440) ...[const SizedBox(height: 28), const _Features()],
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(onPressed: () => context.push('/register'), child: const Text('Criar conta gratuita')),
                  const SizedBox(height: 12),
                  if (google) ...[const GoogleAuthButton(divider: false), const SizedBox(height: 12)],
                  OutlinedButton(onPressed: () => context.push('/login'), child: const Text('Já tenho conta')),
                  if (google) ...[
                    const SizedBox(height: 12),
                    Text.rich(
                      TextSpan(
                        style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                        children: [
                          const TextSpan(text: 'Ao continuar com o Google, aceitas os '),
                          TextSpan(
                            text: 'Termos e a Política de Privacidade',
                            style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w600),
                            recognizer: TapGestureRecognizer()..onTap = () => showPrivacySheet(context),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Features extends StatelessWidget {
  const _Features();

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                Text(body, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      children: [
        item(
          LucideIcons.calendarHeart,
          'Todos os aniversários, num só lugar',
          'Vê quem faz anos hoje, esta semana e todo o ano.',
        ),
        item(
          LucideIcons.bellRing,
          'Lembretes no momento certo',
          'No dia, na véspera ou uma semana antes — tu escolhes.',
        ),
        item(
          LucideIcons.usersRound,
          'Prendas em grupo, contas feitas',
          'Combina o valor com os amigos e paga a quem compra.',
        ),
      ],
    );
  }
}
