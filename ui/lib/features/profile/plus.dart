import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

/// A conta tem o Birthdayly+ agora.
final isPlusProvider = Provider<bool>((ref) => ref.watch(currentUserProvider)?.isPlus ?? false);

/// Antes de uma funcionalidade do Birthdayly+: com o plano, segue (`true`);
/// sem ele, explica o que é e oferece os 30 dias grátis ou os planos.
Future<bool> requirePlus(BuildContext context, WidgetRef ref, {required String feature}) async {
  if (ref.read(isPlusProvider)) return true;
  final trial = ref.read(currentUserProvider)?.plusTrialAvailable ?? false;
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: PlusBadge(large: true)),
            const SizedBox(height: 14),
            Text('$feature é do Birthdayly+', textAlign: TextAlign.center, style: AppTheme.display(ctx, size: 22)),
            const SizedBox(height: 8),
            Text(
              trial
                  ? 'Experimenta todas as funcionalidades durante 30 dias, sem pagar nada.'
                  : 'Vê o que o Birthdayly+ inclui e como ficar com ele.',
              textAlign: TextAlign.center,
              style: ctx.text.bodyMedium?.copyWith(color: ctx.palette.mutedForeground),
            ),
            const SizedBox(height: 18),
            if (trial) FilledButton(onPressed: () => Navigator.pop(ctx, 'trial'), child: const Text('Experimentar 30 dias grátis')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'plans'), child: const Text('Ver os planos')),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return false;
  if (choice == 'trial') {
    final ok = await runGuarded(
      context,
      () => ref.read(authRepositoryProvider).startPlusTrial(),
      success: 'Birthdayly+ ativo durante 30 dias.',
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
            large ? 'Birthdayly+' : 'Plus',
            style: TextStyle(color: Colors.white, fontSize: large ? 13 : 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
