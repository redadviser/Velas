import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/group_models.dart';
import '../auth/auth_widgets.dart';

final _previewProvider = FutureProvider.autoDispose.family<GroupPreview, String>((ref, code) {
  return ref.watch(groupRepositoryProvider)!.previewByCode(code);
});

/// Aberto a partir de um link de convite.
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  bool _joining = false;

  void _close() => context.canPop() ? context.pop() : context.go('/home');

  Future<void> _join() async {
    setState(() => _joining = true);
    String? id;
    final ok = await runGuarded(context, () async {
      final user = ref.read(currentUserProvider)!;
      await ref.read(groupsProvider.notifier).mutate((repo) async {
        id = await repo.joinByCode(widget.code, user.name);
      });
    });
    if (!mounted) return;
    setState(() => _joining = false);
    if (ok && id != null) context.pushReplacement('/groups/$id');
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(_previewProvider(widget.code));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(LucideIcons.x), onPressed: _close),
      ),
      body: SafeArea(
        child: preview.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(_previewProvider(widget.code))),
          data: (g) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
                    child: const Icon(LucideIcons.gift, color: Colors.white, size: 36),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '${g.adminName.isEmpty ? 'Alguém' : g.adminName} convidou-te para',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.palette.mutedForeground),
                ),
                const SizedBox(height: 6),
                Text(g.title, textAlign: TextAlign.center, style: AppTheme.display(context, size: 28)),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  children: [
                    Pill(icon: LucideIcons.cake, label: g.celebrantName),
                    Pill(
                      icon: LucideIcons.usersRound,
                      label: '${g.memberCount} ${g.memberCount == 1 ? 'pessoa' : 'pessoas'}',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  g.closed
                      ? 'A prenda já foi comprada e o grupo está fechado.'
                      : 'Ao entrares, vês o valor combinado, quanto te cabe e a quem pagar.',
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(color: context.palette.mutedForeground),
                ),
                const Spacer(flex: 2),
                if (g.alreadyMember)
                  FilledButton(
                    onPressed: () => context.pushReplacement('/groups/${g.id}'),
                    child: const Text('Abrir grupo'),
                  )
                else if (!g.closed)
                  LoadingButton(label: 'Entrar no grupo', loading: _joining, onPressed: _join),
                const SizedBox(height: 8),
                TextButton(onPressed: _close, child: Text(g.alreadyMember || g.closed ? 'Fechar' : 'Agora não')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
