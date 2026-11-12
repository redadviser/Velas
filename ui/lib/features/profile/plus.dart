import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../services/plus_store.dart';
import '../../core/i18n/translations.dart';

/// A conta tem o Birthdayly+ agora.
final isPlusProvider = Provider<bool>((ref) => ref.watch(currentUserProvider)?.isPlus ?? false);

/// Comprar o Birthdayly+ na loja: com servidor (é ele que confirma a compra) e
/// com o Adapty configurado. Substituído nos testes.
final plusStoreProvider = Provider<PlusStore?>(
  (ref) => ref.watch(apiClientProvider) != null && AdaptyStore.available ? AdaptyStore.instance : null,
);

/// Os planos à venda na loja, com o preço do telemóvel (vazio sem loja).
final storePlansProvider = FutureProvider.autoDispose<List<StorePlan>>((ref) async {
  final store = ref.watch(plusStoreProvider);
  return store == null ? const [] : store.plans();
});

/// A conta no Adapty acompanha a sessão (é por ela que o servidor confirma as compras).
final storeIdentityProvider = Provider<void>((ref) {
  if (ref.watch(plusStoreProvider) == null) return;
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  userId == null ? AdaptyStore.instance.logout() : AdaptyStore.instance.identify(userId);
});

/// Antes de uma funcionalidade do Birthdayly+: com o plano, segue (`true`);
/// sem ele, explica o que é e oferece os 30 dias grátis ou os planos.
Future<bool> requirePlus(BuildContext context, WidgetRef ref, {required String feature}) async {
  if (ref.read(isPlusProvider)) return true;
  final trial = ref.read(currentUserProvider)?.plusTrialAvailable ?? false;
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        // Desliza quando não cabe (letra grande).
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: PlusBadge(large: true)),
              const SizedBox(height: 14),
              Text(
                ctx.tr('{feature} é do Birthdayly+', {'feature': feature}),
                textAlign: TextAlign.center,
                style: AppTheme.display(ctx, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                trial
                    ? ctx.tr('Experimenta todas as funcionalidades durante 30 dias, sem pagar nada.')
                    : ctx.tr('Vê o que o Birthdayly+ inclui e como ficar com ele.'),
                textAlign: TextAlign.center,
                style: ctx.text.bodyMedium?.copyWith(color: ctx.palette.mutedForeground),
              ),
              const SizedBox(height: 18),
              if (trial)
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'trial'),
                  child: Text(ctx.tr('Experimentar 30 dias grátis')),
                ),
              TextButton(onPressed: () => Navigator.pop(ctx, 'plans'), child: Text(ctx.tr('Ver os planos'))),
            ],
          ),
        ),
      ),
    ),
  );
  if (!context.mounted) return false;
  if (choice == 'trial') {
    final ok = await runGuarded(
      context,
      () => ref.read(authRepositoryProvider).startPlusTrial(),
      success: tr('Birthdayly+ ativo durante 30 dias.'),
    );
    return ok && ref.read(isPlusProvider);
  }
  if (choice == 'plans') context.push('/profile/plans');
  return false;
}

/// Etiqueta "Plus" no gradiente da marca, ao lado das funcionalidades pagas.
class PlusBadge extends StatelessWidget {
  const PlusBadge({super.key, this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 7, vertical: large ? 5 : 2),
      decoration: BoxDecoration(gradient: context.palette.brand, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.sparkles, size: large ? 14 : 10, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            large ? 'Birthdayly+' : context.tr('Plus'),
            style: TextStyle(color: Colors.white, fontSize: large ? 13 : 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
