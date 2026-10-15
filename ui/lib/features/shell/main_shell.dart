import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../chat/conversations_list.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mensagens por ler, pedidos de amizade e prendas por pagar (mantém também as conversas
    // atualizadas em tempo real).
    final pending = ref.watch(conversationsBadgeProvider);
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.palette.border)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: [
            const NavigationDestination(icon: Icon(LucideIcons.house), label: 'Início'),
            const NavigationDestination(icon: Icon(LucideIcons.calendarDays), label: 'Agenda'),
            const NavigationDestination(icon: Icon(LucideIcons.usersRound), label: 'Pessoas'),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: pending > 0,
                label: Text(pending > 99 ? '99+' : '$pending'),
                child: const Icon(LucideIcons.gift),
              ),
              label: 'Presentes',
            ),
          ],
        ),
      ),
    );
  }
}
