import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/utils/birthday_utils.dart';
import '../auth/auth_widgets.dart';

/// Preços do Birthdayly+ (ver o plano de negócio).
class PlusPricing {
  const PlusPricing._();

  static const monthly = 2.49;
  static const yearly = 19.99;

  /// Quanto se poupa no anual face a 12 meses (33%).
  static int get yearlySavingPercent => ((1 - yearly / (monthly * 12)) * 100).round();
}

const _freeFeatures = [
  'Lembretes de todos os aniversários',
  'Adicionar dos contactos e pedir datas por link',
  'Prendas em grupo, conversas e amigos',
  'Cartões de parabéns e o teu mural',
];

const _plusFeatures = [
  'Tudo o que o plano Grátis tem',
  'Lembretes avançados: vários por pessoa e à hora que quiseres',
  'Cartões especiais com foto, vídeo ou áudio',
  'Mural com fotografias e um álbum de cada ano',
  'Histórico completo de prendas e mensagens',
  'Widgets no ecrã inicial e temas da app',
];

/// Os planos: Grátis (o de todos) e Birthdayly+. A subscrição ainda não se
/// vende; o botão regista o interesse (POST /me/plus-interest) para medir a procura.
class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  bool _yearly = true;
  bool _sending = false;

  String get _key => 'velas.plusInterest.${ref.read(currentUserProvider)?.id}';
  bool get _registered => ref.read(sharedPrefsProvider).getString(_key) != null;

  Future<void> _trial() async {
    setState(() => _sending = true);
    await runGuarded(
      context,
      () => ref.read(authRepositoryProvider).startPlusTrial(),
      success: 'Birthdayly+ ativo durante 30 dias. Bom proveito!',
    );
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _notifyMe() async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    setState(() => _sending = true);
    final plan = _yearly ? 'yearly' : 'monthly';
    final ok = await runGuarded(context, () => api.post('/me/plus-interest', {'plan': plan}));
    if (ok) await ref.read(sharedPrefsProvider).setString(_key, plan);
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.mutedForeground;
    final user = ref.watch(currentUserProvider);
    final plus = user?.isPlus ?? false;
    final Widget plusAction;
    if (plus) {
      plusAction = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.circleCheck, size: 18, color: context.colors.primary),
          const SizedBox(width: 8),
          Flexible(child: Text('Ativo até ${Fmt.fullDate(user!.plusUntil!)}.')),
        ],
      );
    } else if (user?.plusTrialAvailable ?? false) {
      plusAction = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LoadingButton(label: 'Experimentar 30 dias grátis', loading: _sending, onPressed: _trial),
          if (ref.watch(apiClientProvider) != null)
            _registered
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('Vais ser dos primeiros a saber.', textAlign: TextAlign.center, style: TextStyle(color: muted)),
                  )
                : TextButton(onPressed: _sending ? null : _notifyMe, child: const Text('Avisa-me quando a subscrição chegar')),
        ],
      );
    } else if (ref.watch(apiClientProvider) == null) {
      plusAction = Text('Disponível em breve.', textAlign: TextAlign.center, style: TextStyle(color: muted));
    } else if (_registered) {
      plusAction = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.circleCheck, size: 18, color: context.colors.primary),
          const SizedBox(width: 8),
          const Flexible(child: Text('Vais ser dos primeiros a saber.')),
        ],
      );
    } else {
      plusAction = LoadingButton(label: 'Avisa-me quando chegar', loading: _sending, onPressed: _notifyMe);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Planos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'O essencial é grátis para sempre. O Birthdayly+ junta extras para quem quer ir mais longe.',
              style: context.text.bodyMedium?.copyWith(color: muted),
            ),
          ),
          const SizedBox(height: 16),
          _PlanCarousel(
            cards: [
              _PlusCard(
                yearly: _yearly,
                onPeriod: (y) => setState(() => _yearly = y),
                current: plus,
                action: plusAction,
              ),
              _PlanCard(
                name: 'Grátis',
                price: '0 €',
                badge: plus ? null : const Pill(label: 'O teu plano', dense: true),
                features: _freeFeatures,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'As prendas em grupo pagam-se diretamente a quem compra (MB WAY, Revolut, PayPal ou em mão), sem custos.',
              style: context.text.bodySmall?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Os planos lado a lado, a deslizar na horizontal: cada cartão ocupa quase a
/// largura toda (o seguinte espreita à direita), todos com a mesma altura, e o
/// deslizar pára sempre num cartão.
class _PlanCarousel extends StatefulWidget {
  const _PlanCarousel({required this.cards});

  final List<Widget> cards;

  @override
  State<_PlanCarousel> createState() => _PlanCarouselState();
}

class _PlanCarouselState extends State<_PlanCarousel> {
  static const _gap = 12.0;
  static const _side = 20.0;
  final _scroll = ScrollController();
  int _page = 0;
  double _step = 1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final page = (_scroll.offset / _step).round().clamp(0, widget.cards.length - 1);
      if (page != _page) setState(() => _page = page);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// No fim de um deslize, acerta no cartão mais próximo.
  bool _snap(ScrollEndNotification n) {
    final target = (_scroll.offset / _step).round() * _step;
    if ((target - _scroll.offset).abs() > 1) {
      Future.microtask(
        () => _scroll.animateTo(
          target.clamp(0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - _side * 2 - 28).clamp(240.0, 440.0);
        _step = width + _gap;
        return Column(
          children: [
            NotificationListener<ScrollEndNotification>(
              onNotification: _snap,
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: _side),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, card) in widget.cards.indexed) ...[
                        if (i > 0) const SizedBox(width: _gap),
                        SizedBox(width: width, child: card),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.cards.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page ? context.colors.primary : context.palette.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.name, required this.price, required this.features, this.badge});

  final String name;
  final String price;
  final Widget? badge;
  final List<String> features;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: _PlanBody(name: name, price: price, badge: badge, features: features),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.name, required this.price, required this.features, this.badge, this.period, this.note});

  final String name;
  final String price;
  final String? period;
  final String? note;
  final Widget? badge;
  final List<String> features;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.mutedForeground;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(name, style: AppTheme.display(context, size: 22))),
            ?badge,
          ],
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: price, style: AppTheme.display(context, size: 28)),
              if (period != null) TextSpan(text: ' $period', style: TextStyle(color: muted)),
            ],
          ),
        ),
        if (note != null) Text(note!, style: context.text.bodySmall?.copyWith(color: context.colors.primary)),
        const SizedBox(height: 14),
        for (final f in features)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(LucideIcons.check, size: 16, color: context.colors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(f, style: context.text.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

/// O cartão do Birthdayly+, com a moldura no gradiente da marca.
class _PlusCard extends StatelessWidget {
  const _PlusCard({required this.yearly, required this.onPeriod, required this.action, this.current = false});

  final bool yearly;
  final bool current;
  final ValueChanged<bool> onPeriod;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final price = yearly ? PlusPricing.yearly : PlusPricing.monthly;
    String euros(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(gradient: context.palette.brand, borderRadius: BorderRadius.circular(22)),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: context.palette.card, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Mensal')),
                ButtonSegment(value: true, label: Text('Anual')),
              ],
              selected: {yearly},
              onSelectionChanged: (s) => onPeriod(s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 16),
            _PlanBody(
              name: 'Birthdayly+',
              price: euros(price),
              period: yearly ? '/ano' : '/mês',
              note: yearly
                  ? 'Equivale a ${euros(PlusPricing.yearly / 12)}/mês · poupas ${PlusPricing.yearlySavingPercent}%'
                  : null,
              badge: Pill(label: current ? 'O teu plano' : 'Em breve', dense: true),
              features: _plusFeatures,
            ),
            const SizedBox(height: 8),
            action,
          ],
        ),
      ),
    );
  }
}
