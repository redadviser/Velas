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
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
            'O essencial é grátis para sempre. O Birthdayly+ junta extras para quem quer ir mais longe.',
            style: context.text.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: 16),
          _PlanCard(
            name: 'Grátis',
            price: '0 €',
            badge: plus ? null : const Pill(label: 'O teu plano', dense: true),
            features: _freeFeatures,
          ),
          const SizedBox(height: 16),
          _PlusCard(
            yearly: _yearly,
            onPeriod: (y) => setState(() => _yearly = y),
            current: plus,
            action: plusAction,
          ),
          const SizedBox(height: 20),
          Text(
            'Pagar a tua parte de uma prenda em grupo dentro da app tem uma taxa de serviço de 0,39 € por pagamento. '
            'Pagar por MB WAY diretamente a quem compra é sempre grátis.',
            style: context.text.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
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
