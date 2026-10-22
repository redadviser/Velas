import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';

/// Tamanho da letra, contraste e animações (guardados neste telemóvel; somam-se
/// às definições de acessibilidade do sistema).
class AccessibilityScreen extends ConsumerWidget {
  const AccessibilityScreen({super.key});

  static String _label(double? v) => v == null ? 'Do telemóvel' : '${(v * 100).round()}%';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a11y = ref.watch(accessibilityProvider);
    final ctrl = ref.read(accessibilityProvider.notifier);
    final muted = context.palette.mutedForeground;
    const scales = AccessibilityController.scales;
    // Posição no seletor: 0 = do telemóvel, depois cada tamanho.
    final index = a11y.textScale == null ? 0 : (scales.indexOf(a11y.textScale!) + 1).clamp(1, scales.length);

    return Scaffold(
      appBar: AppBar(title: const Text('Acessibilidade')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text('Tamanho do texto', style: context.text.titleSmall),
          const SizedBox(height: 4),
          Text(_label(a11y.textScale), style: context.text.bodySmall?.copyWith(color: muted)),
          Row(
            children: [
              Icon(LucideIcons.aLargeSmall, size: 16, color: muted),
              Expanded(
                child: Slider(
                  value: index.toDouble(),
                  min: 0,
                  max: scales.length.toDouble(),
                  divisions: scales.length,
                  label: _label(index == 0 ? null : scales[index - 1]),
                  onChanged: (v) => ctrl.setTextScale(v.round() == 0 ? null : scales[v.round() - 1]),
                ),
              ),
              Icon(LucideIcons.aLargeSmall, size: 24, color: muted),
            ],
          ),
          AppCard(
            color: context.palette.accent,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ana faz anos amanhã', style: AppTheme.display(context, size: 20)),
                const SizedBox(height: 4),
                Text(
                  'Assim fica o texto na app. Os títulos e os botões crescem na mesma proporção.',
                  style: context.text.bodyMedium?.copyWith(color: context.palette.accentForeground),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(LucideIcons.contrast, size: 20),
                  title: const Text('Contraste alto'),
                  subtitle: const Text('Texto secundário e contornos mais fortes'),
                  value: a11y.highContrast,
                  onChanged: ctrl.setHighContrast,
                ),
                const Divider(indent: 16, endIndent: 16),
                SwitchListTile(
                  secondary: const Icon(LucideIcons.zapOff, size: 20),
                  title: const Text('Reduzir animações'),
                  subtitle: const Text('Mudanças de ecrã e efeitos sem movimento'),
                  value: a11y.reduceMotion,
                  onChanged: ctrl.setReduceMotion,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'A app também segue as definições de acessibilidade do telemóvel, como o tamanho da letra, o leitor de ecrã '
            '(TalkBack ou VoiceOver) e o contraste do sistema.',
            style: context.text.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}
