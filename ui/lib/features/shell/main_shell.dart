import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../chat/conversations_list.dart';
import '../people/birthday_request.dart';
import '../special/special_dates_screen.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mensagens por ler, pedidos de amizade e prendas por pagar (mantém também as conversas
    // atualizadas em tempo real).
    final pending = ref.watch(conversationsBadgeProvider);
    void go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

    return Scaffold(
      body: shell,
      bottomNavigationBar: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.palette.card.withValues(alpha: 0.94),
                  border: Border(top: BorderSide(color: context.palette.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 66,
                    child: Row(
                      children: [
                        _Tab(icon: LucideIcons.house, label: 'Início', index: 0, shell: shell, onTap: go),
                        _Tab(icon: LucideIcons.usersRound, label: 'Pessoas', index: 1, shell: shell, onTap: go),
                        // A coluna toda abre o menu; o botão desenhado por cima sai da barra.
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            excludeFromSemantics: true,
                            onTap: () => showAddSheet(context, ref),
                          ),
                        ),
                        _Tab(
                          icon: LucideIcons.gift,
                          label: 'Prendas',
                          index: 2,
                          shell: shell,
                          onTap: go,
                          badge: pending,
                        ),
                        _Tab(icon: LucideIcons.circleUserRound, label: 'Perfil', index: 3, shell: shell, onTap: go),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -18,
            left: 0,
            right: 0,
            child: Center(child: _AddButton(onTap: () => showAddSheet(context, ref))),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.index,
    required this.shell,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final int index;
  final StatefulNavigationShell shell;
  final ValueChanged<int> onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final selected = shell.currentIndex == index;
    final color = selected ? context.colors.primary : context.palette.mutedForeground;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: () => onTap(index),
          radius: 36,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text(badge > 99 ? '99+' : '$badge'),
                child: AnimatedScale(
                  scale: selected ? 1.08 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(icon, size: 23, color: color),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botão central inclinado, como um autocolante, que abre o menu de adicionar.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.05,
      child: Tooltip(
        message: 'Adicionar',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            boxShadow: [
              BoxShadow(
                color: context.colors.primary.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: context.colors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox.square(
                dimension: 56,
                child: Transform.rotate(
                  angle: 0.05,
                  child: Icon(LucideIcons.plus, size: 28, color: context.colors.onPrimary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showAddSheet(BuildContext context, WidgetRef ref) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: context.palette.card,
  builder: (_) => _AddSheet(host: context, ref: ref),
);

/// "O que queres adicionar?" e, para uma pessoa, o segundo passo "Quem queres guardar?".
class _AddSheet extends StatefulWidget {
  const _AddSheet({required this.host, required this.ref});

  /// Contexto de quem abriu a folha (continua válido depois de a fechar).
  final BuildContext host;
  final WidgetRef ref;

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  bool _person = false;

  void _go(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  Widget _option(IconData icon, String title, String subtitle, VoidCallback action, {bool last = false}) => Column(
    children: [
      InkWell(
        onTap: () => _go(action),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              IconBadge(icon: icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleSmall),
                    const SizedBox(height: 2),
                    Text(subtitle, style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground)),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 20, color: context.colors.onSurface),
            ],
          ),
        ),
      ),
      if (!last) const Divider(),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final ref = widget.ref;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_person)
                    IconButton(
                      tooltip: 'Voltar',
                      onPressed: () => setState(() => _person = false),
                      icon: const Icon(LucideIcons.arrowLeft),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  Expanded(
                    child: Text(
                      _person ? 'Quem queres guardar?' : 'O que queres adicionar?',
                      style: AppTheme.display(context, size: 21),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (!_person) ...[
                InkWell(
                  onTap: () => setState(() => _person = true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        const IconBadge(icon: LucideIcons.user),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Uma pessoa', style: context.text.titleSmall),
                              const SizedBox(height: 2),
                              Text(
                                'Manual, contactos, calendário ou por link',
                                style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                              ),
                            ],
                          ),
                        ),
                        Icon(LucideIcons.chevronRight, size: 20, color: context.colors.onSurface),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                _option(
                  LucideIcons.heart,
                  'Uma data especial',
                  'Aniversários, Dia da Mãe ou à medida',
                  () => showSpecialDateEditor(host, ref),
                ),
                _option(
                  LucideIcons.gift,
                  'Um grupo de prenda',
                  'Junta amigos e divide o valor',
                  () => host.push('/groups/new'),
                ),
                _option(
                  LucideIcons.sparkles,
                  'Uma festa surpresa',
                  'Convida, distribui tarefas e celebra',
                  () => host.push('/parties/new'),
                  last: true,
                ),
              ] else ...[
                _option(
                  LucideIcons.userPlus,
                  'Adicionar manualmente',
                  'Nome, data, ano opcional e categoria',
                  () => host.push('/person/new'),
                ),
                _option(
                  LucideIcons.contactRound,
                  'Escolher dos contactos',
                  'Encontra alguém na lista do telemóvel',
                  () => host.push('/people/import'),
                ),
                _option(
                  LucideIcons.calendarDays,
                  'Importar do calendário',
                  'Escolhe entre as datas encontradas',
                  () => host.push('/people/import?from=calendar'),
                ),
                _option(
                  LucideIcons.link,
                  'Pedir por link',
                  'Os amigos escrevem a data deles',
                  () => shareBirthdayRequest(host, ref),
                  last: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
