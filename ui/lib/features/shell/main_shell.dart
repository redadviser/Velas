import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/translations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../chat/conversations_list.dart';
import '../gifts/gift_widgets.dart';
import '../groups/group_widgets.dart';
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
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.palette.card,
              border: Border(top: BorderSide(color: context.palette.border)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 66,
                child: Row(
                  children: [
                    _Tab(icon: LucideIcons.house, label: context.tr('Início'), index: 0, shell: shell, onTap: go),
                    _Tab(icon: LucideIcons.usersRound, label: context.tr('Pessoas'), index: 1, shell: shell, onTap: go),
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
                      label: context.tr('Prendas'),
                      index: 2,
                      shell: shell,
                      onTap: go,
                      badge: pending,
                    ),
                    _Tab(icon: LucideIcons.user, label: context.tr('Perfil'), index: 3, shell: shell, onTap: go),
                  ],
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
        message: context.tr('Adicionar'),
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

enum _Step { menu, person, gift }

/// "O que queres adicionar?" e o segundo passo de uma pessoa ("Quem queres
/// guardar?") ou das prendas (criar grupo, entrar com código ou nova ideia).
class _AddSheet extends StatefulWidget {
  const _AddSheet({required this.host, required this.ref});

  /// Contexto de quem abriu a folha (continua válido depois de a fechar).
  final BuildContext host;
  final WidgetRef ref;

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  var _step = _Step.menu;

  void _go(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  Widget _option(IconData icon, String title, String subtitle, VoidCallback action, {bool last = false}) =>
      _tile(icon, title, subtitle, () => _go(action), last: last);

  /// Abre um segundo passo dentro da folha.
  Widget _next(IconData icon, String title, String subtitle, _Step step) =>
      _tile(icon, title, subtitle, () => setState(() => _step = step), last: true);

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap, {bool last = false}) => Column(
    children: [
      InkWell(
        onTap: onTap,
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
    final codes = ref.read(groupRepositoryProvider)?.supportsInvites ?? false;
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
                  if (_step != _Step.menu)
                    IconButton(
                      tooltip: context.tr('Voltar'),
                      onPressed: () => setState(() => _step = _Step.menu),
                      icon: const Icon(LucideIcons.arrowLeft),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  Expanded(
                    child: Text(switch (_step) {
                      _Step.menu => context.tr('O que queres adicionar?'),
                      _Step.person => context.tr('Quem queres guardar?'),
                      _Step.gift => context.tr('Prendas'),
                    }, style: AppTheme.display(context, size: 21)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (_step == _Step.menu) ...[
                _next(
                  LucideIcons.user,
                  context.tr('Uma pessoa'),
                  context.tr('Manual, contactos, calendário ou por link'),
                  _Step.person,
                ),
                const Divider(),
                _option(
                  LucideIcons.heart,
                  context.tr('Uma data especial'),
                  context.tr('Aniversários, Dia da Mãe ou à medida'),
                  () => showSpecialDateEditor(host, ref),
                ),
                _next(LucideIcons.gift, context.tr('Prendas'), context.tr('Grupos, códigos e ideias'), _Step.gift),
                const Divider(),
                _option(
                  LucideIcons.partyPopper,
                  context.tr('Uma festa surpresa'),
                  context.tr('Convida, distribui tarefas e celebra'),
                  () => host.push('/parties/new'),
                  last: true,
                ),
              ] else if (_step == _Step.gift) ...[
                _option(
                  LucideIcons.usersRound,
                  context.tr('Criar grupo'),
                  context.tr('Junta amigos e divide o valor'),
                  () => host.push('/groups/new'),
                ),
                if (codes)
                  _option(
                    LucideIcons.ticket,
                    context.tr('Tenho um código'),
                    context.tr('De uma prenda em grupo ou de uma festa surpresa'),
                    () => showJoinCodeSheet(host, ref),
                  ),
                _option(
                  LucideIcons.lightbulb,
                  context.tr('Nova ideia'),
                  context.tr('Guarda uma ideia para alguém'),
                  () => pickPersonThenAddGift(host, ref),
                  last: true,
                ),
              ] else ...[
                _option(
                  LucideIcons.userPlus,
                  context.tr('Adicionar manualmente'),
                  context.tr('Nome, data, ano opcional e categoria'),
                  () => host.push('/person/new'),
                ),
                _option(
                  LucideIcons.contactRound,
                  context.tr('Escolher dos contactos'),
                  context.tr('Encontra alguém na lista do telemóvel'),
                  () => host.push('/people/import'),
                ),
                _option(
                  LucideIcons.calendarDays,
                  context.tr('Importar do calendário'),
                  context.tr('Escolhe entre as datas encontradas'),
                  () => host.push('/people/import?from=calendar'),
                ),
                _option(
                  LucideIcons.link,
                  context.tr('Pedir por link'),
                  context.tr('Os amigos escrevem a data deles'),
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
