import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/utils/birthday_utils.dart';
import '../../services/plus_store.dart';
import '../auth/auth_widgets.dart';
import 'plus.dart';
import '../../core/i18n/translations.dart';

/// Preços do Birthdayly+ (ver o plano de negócio).
class PlusPricing {
  const PlusPricing._();

  static const monthly = 2.49;
  static const yearly = 19.99;

  /// Quanto se poupa no anual face a 12 meses (33%).
  static int get yearlySavingPercent => ((1 - yearly / (monthly * 12)) * 100).round();
}

List<String> get _freeFeatures => [
  tr('Lembretes de todos os aniversários'),
  tr('Adicionar dos contactos e pedir datas por link'),
  tr('Prendas em grupo, conversas e amigos'),
  tr('Cartões de parabéns e o teu mural'),
];

List<String> get _plusFeatures => [
  tr('Tudo o que o plano Grátis tem'),
  tr('Lembretes avançados: vários por pessoa e à hora que quiseres'),
  tr('Cartões especiais com foto, vídeo ou áudio'),
  tr('Mural com fotografias e um álbum de cada ano'),
  tr('Histórico completo de prendas e mensagens'),
  tr('Widgets no ecrã inicial e temas da app'),
];

/// Os planos: Grátis (o de todos) e Birthdayly+. Com a loja ligada (Adapty),
/// compra-se aqui, com o preço da loja, e o servidor confirma a compra. Sem
/// ela, o botão regista o interesse (POST /me/plus-interest) para medir a procura.
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
      success: tr('Birthdayly+ ativo durante 30 dias. Bom proveito!'),
    );
    if (mounted) setState(() => _sending = false);
  }

  /// Comprar na loja; o servidor confirma com o Adapty e o perfil passa a ter o plano.
  Future<void> _buy(PlusStore store, StorePlan plan) async {
    setState(() => _sending = true);
    var bought = false;
    final ok = await runGuarded(context, () async {
      bought = await store.buy(plan);
      if (bought) await ref.read(authRepositoryProvider).syncPlus();
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok && bought) showMessage(context, context.tr('Bem-vindo ao Birthdayly+! 🎉'));
  }

  Future<void> _restore(PlusStore store) async {
    setState(() => _sending = true);
    final ok = await runGuarded(context, () async {
      await store.restore();
      await ref.read(authRepositoryProvider).syncPlus();
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) return;
    final plus = ref.read(currentUserProvider)?.isPlus ?? false;
    showMessage(
      context,
      plus ? context.tr('Compras restauradas.') : context.tr('Não encontrámos o Birthdayly+ nesta conta da loja.'),
    );
  }

  /// As subscrições geridas pela loja (cancelar, mudar de plano).
  Future<void> _manage() => launchUrl(
    Uri.parse(
      Platform.isIOS
          ? 'https://apps.apple.com/account/subscriptions'
          : 'https://play.google.com/store/account/subscriptions',
    ),
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);

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
    final store = ref.watch(plusStoreProvider);
    final storePlans = ref.watch(storePlansProvider);
    final storePlan = storePlans.value?.where((p) => p.yearly == _yearly).firstOrNull;
    final Widget plusAction;
    if (plus) {
      plusAction = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.circleCheck, size: 18, color: context.colors.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  user!.plusUntil!.year >= 9999
                      ? context.tr('Ativo para sempre.{test}', {
                          'test': user.planDebug ? context.tr(' (modo de testes)') : '',
                        })
                      : context.tr('Ativo até {date}.{test}', {
                          'date': Fmt.fullDate(user.plusUntil!),
                          'test': user.planDebug ? context.tr(' (modo de testes)') : '',
                        }),
                ),
              ),
            ],
          ),
          if (store != null && !user.planDebug)
            TextButton(onPressed: _manage, child: Text(context.tr('Gerir subscrição'))),
        ],
      );
    } else if (store != null) {
      plusAction = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (storePlan != null)
            LoadingButton(
              label: _yearly
                  ? context.tr('Assinar por {price}/ano', {'price': storePlan.price})
                  : context.tr('Assinar por {price}/mês', {'price': storePlan.price}),
              loading: _sending,
              onPressed: () => _buy(store, storePlan),
            )
          else
            Text(
              storePlans.isLoading
                  ? context.tr('A carregar os preços…')
                  : context.tr('O Birthdayly+ não está disponível de momento.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          if (user?.plusTrialAvailable ?? false)
            TextButton(onPressed: _sending ? null : _trial, child: Text(context.tr('Experimentar 30 dias grátis'))),
          TextButton(onPressed: _sending ? null : () => _restore(store), child: Text(context.tr('Restaurar compras'))),
        ],
      );
    } else if (user?.plusTrialAvailable ?? false) {
      plusAction = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LoadingButton(label: context.tr('Experimentar 30 dias grátis'), loading: _sending, onPressed: _trial),
          if (ref.watch(apiClientProvider) != null)
            _registered
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      context.tr('Vais ser dos primeiros a saber.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                  )
                : TextButton(
                    onPressed: _sending ? null : _notifyMe,
                    child: Text(context.tr('Avisa-me quando a subscrição chegar')),
                  ),
        ],
      );
    } else if (ref.watch(apiClientProvider) == null) {
      plusAction = Text(
        context.tr('Disponível em breve.'),
        textAlign: TextAlign.center,
        style: TextStyle(color: muted),
      );
    } else if (_registered) {
      plusAction = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.circleCheck, size: 18, color: context.colors.primary),
          const SizedBox(width: 8),
          Flexible(child: Text(context.tr('Vais ser dos primeiros a saber.'))),
        ],
      );
    } else {
      plusAction = LoadingButton(label: context.tr('Avisa-me quando chegar'), loading: _sending, onPressed: _notifyMe);
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Planos'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              context.tr('O essencial é grátis para sempre. O Birthdayly+ junta extras para quem quer ir mais longe.'),
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
                storePlans: storePlans.value ?? const [],
                forSale: store != null,
              ),
              _PlanCard(
                name: context.tr('Grátis'),
                price: '0 €',
                badge: plus ? null : Pill(label: context.tr('O teu plano'), dense: true),
                features: _freeFeatures,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              context.tr(
                'As prendas em grupo pagam-se diretamente a quem compra (MB WAY, Revolut, PayPal ou em mão), sem custos.',
              ),
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
  const _PlanBody({
    required this.name,
    required this.price,
    required this.features,
    this.badge,
    this.period,
    this.note,
  });

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
            if (badge != null) Flexible(child: badge!),
          ],
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: price, style: AppTheme.display(context, size: 28)),
              if (period != null)
                TextSpan(
                  text: ' $period',
                  style: TextStyle(color: muted),
                ),
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
  const _PlusCard({
    required this.yearly,
    required this.onPeriod,
    required this.action,
    this.current = false,
    this.storePlans = const [],
    this.forSale = false,
  });

  final bool yearly;
  final bool current;
  final ValueChanged<bool> onPeriod;
  final Widget action;

  /// Os preços da loja (na moeda do telemóvel); sem eles, os de referência.
  final List<StorePlan> storePlans;

  /// À venda na loja (o selo deixa de dizer "Em breve").
  final bool forSale;

  @override
  Widget build(BuildContext context) {
    String euros(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';
    final monthlyPlan = storePlans.where((p) => !p.yearly).firstOrNull;
    final yearlyPlan = storePlans.where((p) => p.yearly).firstOrNull;
    final storePlan = yearly ? yearlyPlan : monthlyPlan;
    final priceText = storePlan?.price ?? euros(yearly ? PlusPricing.yearly : PlusPricing.monthly);
    // Quanto se poupa no anual face a 12 meses (com os preços da loja, se houver os dois).
    final saving = monthlyPlan != null && yearlyPlan != null && monthlyPlan.amount > 0
        ? ((1 - yearlyPlan.amount / (monthlyPlan.amount * 12)) * 100).round()
        : storePlans.isEmpty
        ? PlusPricing.yearlySavingPercent
        : null;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(gradient: context.palette.brand, borderRadius: BorderRadius.circular(22)),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: context.palette.card, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // O SegmentedButton tem altura fixa: acima de 120% o texto saía do botão.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(context.tr('Mensal'))),
                  ButtonSegment(value: true, label: Text(context.tr('Anual'))),
                ],
                selected: {yearly},
                onSelectionChanged: (s) => onPeriod(s.first),
                showSelectedIcon: false,
              ),
            ),
            const SizedBox(height: 16),
            _PlanBody(
              name: 'Birthdayly+',
              price: priceText,
              period: yearly ? context.tr('/ano') : context.tr('/mês'),
              note: !yearly
                  ? null
                  : storePlans.isEmpty
                  ? context.tr('Equivale a {amount}/mês · poupas {percent}%', {
                      'amount': euros(PlusPricing.yearly / 12),
                      'percent': PlusPricing.yearlySavingPercent,
                    })
                  : saving != null && saving > 0
                  ? context.tr('Poupas {percent}% face ao mensal', {'percent': saving})
                  : null,
              badge: current
                  ? Pill(label: context.tr('O teu plano'), dense: true)
                  : forSale
                  ? null
                  : Pill(label: context.tr('Em breve'), dense: true),
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
