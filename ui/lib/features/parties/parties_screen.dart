import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../groups/group_widgets.dart';
import 'party_widgets.dart';
import '../../core/i18n/translations.dart';

class PartiesScreen extends ConsumerWidget {
  const PartiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(partiesProvider);
    final parties = [...?async.value]..sort((a, b) => a.isPast == b.isPast ? 0 : (a.isPast ? 1 : -1));
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Festas surpresa')),
        actions: [
          IconButton(
            tooltip: context.tr('Entrar com código'),
            icon: const Icon(LucideIcons.ticket),
            onPressed: () => showJoinCodeSheet(context, ref),
          ),
        ],
      ),
      body: async.hasError && parties.isEmpty
          ? ErrorRetry(error: async.error!, onRetry: () => ref.invalidate(partiesProvider))
          : RefreshIndicator(
              onRefresh: () => ref.read(partiesProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                children: [
                  if (parties.isEmpty && !async.isLoading)
                    EmptyState(
                      icon: LucideIcons.partyPopper,
                      title: context.tr('Surpresas que ficam na memória'),
                      message: context.tr(
                        'Convida os amigos, vê quem vai e dividam as tarefas, longe dos olhos do aniversariante.',
                      ),
                      action: FilledButton.icon(
                        onPressed: () => context.push('/parties/new'),
                        icon: const Icon(LucideIcons.partyPopper, size: 18),
                        label: Text(context.tr('Organizar uma festa')),
                        style: FilledButton.styleFrom(minimumSize: const Size(240, 52)),
                      ),
                    )
                  else ...[
                    for (final p in parties) ...[
                      Opacity(
                        opacity: p.isPast ? 0.6 : 1,
                        child: PartyCard(party: p),
                      ),
                      const SizedBox(height: 12),
                    ],
                    DashedButton(
                      icon: LucideIcons.plus,
                      label: context.tr('Organizar outra festa'),
                      onTap: () => context.push('/parties/new'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => showJoinCodeSheet(context, ref),
                      icon: Icon(LucideIcons.ticket, size: 18, color: context.palette.accentForeground),
                      label: Text(context.tr('Tenho um código de convite')),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
