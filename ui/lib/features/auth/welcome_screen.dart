import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import 'auth_widgets.dart';
import 'register_screen.dart';

/// Um destaque do carrossel de boas-vindas (fotografias em assets/images/welcome).
class _Slide {
  const _Slide({required this.image, required this.eyebrow, required this.title, required this.body});

  final String image;
  final String eyebrow;
  final String title;
  final String body;
}

const _slides = [
  _Slide(
    image: 'assets/images/welcome/candles.jpg',
    eyebrow: 'ANIVERSÁRIOS',
    title: 'Nunca mais te esqueças de quem importa.',
    body: 'Os aniversários da família e dos amigos num só lugar, sempre à mão.',
  ),
  _Slide(
    image: 'assets/images/welcome/wish.jpg',
    eyebrow: 'LEMBRETES',
    title: 'Chega a tempo de todos os parabéns.',
    body: 'Avisos no dia, na véspera ou uma semana antes, com mensagens prontas a enviar.',
  ),
  _Slide(
    image: 'assets/images/welcome/gift.jpg',
    eyebrow: 'PRENDAS EM GRUPO',
    title: 'Prendas a meias, sem contas complicadas.',
    body: 'Junta os amigos, divide o valor e vê quem já pagou, tudo na app.',
  ),
];

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  static const _interval = Duration(seconds: 6);

  // Página inicial alta para o carrossel poder avançar sempre para a direita.
  final _pages = PageController(initialPage: _slides.length * 1000);
  int _page = _slides.length * 1000;
  Timer? _timer;
  bool _precached = false;

  int get _index => _page % _slides.length;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      for (final s in _slides) {
        precacheImage(AssetImage(s.image), context);
      }
    }
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  /// Avança sozinho, exceto com "reduzir movimento" ativo. Recomeça a contar
  /// sempre que a página muda (também quando é o utilizador a deslizar).
  void _restartTimer() {
    _timer?.cancel();
    if (MediaQuery.of(context).disableAnimations) return;
    _timer = Timer(_interval, () {
      if (_pages.hasClients) {
        _pages.nextPage(duration: const Duration(milliseconds: 700), curve: Curves.easeInOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final google = ref.watch(authRepositoryProvider).supportsGoogle;
    final media = MediaQuery.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _Backdrop(image: _slides[_index].image),
            const _Scrim(),
            Padding(
              padding: EdgeInsets.fromLTRB(0, media.padding.top + 16, 0, media.padding.bottom + 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Align(alignment: Alignment.centerLeft, child: BrandMark(size: 34, onGradient: true)),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      onPageChanged: (page) {
                        setState(() => _page = page);
                        _restartTimer();
                      },
                      itemBuilder: (_, page) => _SlideText(_slides[page % _slides.length]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                    child: _Dots(count: _slides.length, active: _index),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _Actions(google: google),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fotografia de fundo: troca com um fade e aproxima-se devagar (efeito Ken Burns).
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.image});

  final String image;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 900),
    switchInCurve: Curves.easeOut,
    switchOutCurve: Curves.easeIn,
    layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
    child: TweenAnimationBuilder<double>(
      key: ValueKey(image),
      tween: Tween(begin: 1, end: 1.08),
      duration: const Duration(seconds: 9),
      curve: Curves.easeOut,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: Image.asset(image, fit: BoxFit.cover, gaplessPlayback: true),
    ),
  );
}

/// Escurece o topo (logótipo e barra de estado) e sobretudo a base (texto e botões).
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0, 0.18, 0.4, 0.6, 1],
        colors: [Color(0x99000000), Color(0x00000000), Color(0x33000000), Color(0xE00D0806), Color(0xF50D0806)],
      ),
    ),
  );
}

class _SlideText extends StatelessWidget {
  const _SlideText(this.slide);

  final _Slide slide;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Align(
      alignment: Alignment.bottomLeft,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              slide.eyebrow,
              style: const TextStyle(
                color: AppColors.darkPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 12),
            Text(slide.title, style: AppTheme.display(context, size: 34, color: Colors.white)),
            const SizedBox(height: 12),
            Text(slide.body, style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 16, height: 1.45)),
          ],
        ),
      ),
    ),
  );
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(right: 6),
          width: i == active ? 24 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: i == active ? 1 : 0.35),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
    ],
  );
}

/// Botões sobre a fotografia: o principal com a cor da marca e o do Google
/// translúcido, para não competirem.
class _Actions extends StatelessWidget {
  const _Actions({required this.google});

  final bool google;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: 0.12),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
    ).merge(theme.outlinedButtonTheme.style);
    final muted = Colors.white.withValues(alpha: 0.7);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(onPressed: () => context.push('/register'), child: const Text('Criar conta gratuita')),
        if (google) ...[
          const SizedBox(height: 12),
          Theme(
            data: theme.copyWith(outlinedButtonTheme: OutlinedButtonThemeData(style: glass)),
            child: const GoogleAuthButton(divider: false),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Já tens conta?', style: TextStyle(color: muted, fontSize: 15)),
            TextButton(
              onPressed: () => context.push('/login'),
              style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.all(8)),
              child: const Text('Entrar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ],
        ),
        if (google)
          Text.rich(
            TextSpan(
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12, height: 1.4),
              children: [
                const TextSpan(text: 'Ao continuar com o Google, aceitas os '),
                TextSpan(
                  text: 'Termos e a Política de Privacidade',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  recognizer: TapGestureRecognizer()..onTap = () => showPrivacySheet(context),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }
}
