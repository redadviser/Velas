import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.palette.border)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: const [
            NavigationDestination(icon: Icon(LucideIcons.house), label: 'Início'),
            NavigationDestination(icon: Icon(LucideIcons.calendarDays), label: 'Agenda'),
            NavigationDestination(icon: Icon(LucideIcons.usersRound), label: 'Pessoas'),
            NavigationDestination(icon: Icon(LucideIcons.gift), label: 'Presentes'),
          ],
        ),
      ),
    );
  }
}
