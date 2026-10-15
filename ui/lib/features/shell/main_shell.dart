import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/theme/app_colors.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mensagens por ler e pedidos de amizade (também mantém a lista atualizada em tempo real).
    final pending = ref.watch(unreadTotalProvider) + ref.watch(incomingFriendRequestsProvider);
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
            const NavigationDestination(icon: Icon(LucideIcons.gift), label: 'Presentes'),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: pending > 0,
                label: Text(pending > 99 ? '99+' : '$pending'),
                child: const Icon(LucideIcons.messageCircle),
              ),
              label: 'Conversas',
            ),
          ],
        ),
      ),
    );
  }
}
