import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/i18n/translations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../data/models/payments_models.dart';

/// Estado de "Receber pagamentos na app" (conta Stripe de quem compra a prenda).
final payoutStatusProvider = FutureProvider.autoDispose<PayoutStatus>((ref) async {
  final repo = ref.watch(paymentsRepositoryProvider);
  if (repo == null) return PayoutStatus.off;
  return repo.payoutStatus();
});

/// Ligar a conta Stripe para os amigos pagarem a parte dentro da app.
/// Não aparece se a Birthdayly não tiver pagamentos na app ligados.
class PayoutsCard extends ConsumerStatefulWidget {
  const PayoutsCard({super.key});

  @override
  ConsumerState<PayoutsCard> createState() => _PayoutsCardState();
}

class _PayoutsCardState extends ConsumerState<PayoutsCard> with WidgetsBindingObserver {
  bool _busy = false;
  bool _openedStripe = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Ao voltar da página da Stripe, vê se a conta já pode receber.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openedStripe) {
      _openedStripe = false;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final repo = ref.read(paymentsRepositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    await runGuarded(context, () async {
      await repo.refreshPayouts();
      ref.invalidate(payoutStatusProvider);
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _connect() async {
    final repo = ref.read(paymentsRepositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    await runGuarded(context, () async {
      final url = await repo.startOnboarding();
      _openedStripe = true;
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView).catchError((_) => false);
      if (!ok) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(payoutStatusProvider).value;
    if (status == null || !status.enabled) return const SizedBox.shrink();
    final muted = context.palette.mutedForeground;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  status.ready ? LucideIcons.circleCheck : LucideIcons.landmark,
                  color: status.ready ? context.palette.success : context.colors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(context.tr(Keys.payoutsTitle), style: context.text.titleSmall)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              status.ready
                  ? context.tr(Keys.payoutsReady)
                  : status.connected
                  ? context.tr(Keys.payoutsPending)
                  : context.tr(Keys.payoutsHint),
              style: context.text.bodySmall?.copyWith(color: status.ready ? context.palette.success : muted),
            ),
            if (!status.ready) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _connect,
                icon: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.externalLink, size: 18),
                label: Text(context.tr(status.connected ? Keys.payoutsContinue : Keys.payoutsConnect)),
              ),
              if (status.connected)
                TextButton(onPressed: _busy ? null : _refresh, child: Text(context.tr(Keys.payoutsRefresh))),
            ],
          ],
        ),
      ),
    );
  }
}
