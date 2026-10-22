import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/utils/text.dart';
import '../../core/widgets/common.dart';
import 'birthday_request.dart';

/// As datas deixadas pelo link, à espera de confirmação: só entram na lista de
/// aniversários depois de aceites (assim, nomes inventados nunca lá chegam).
class PendingAnswersScreen extends ConsumerStatefulWidget {
  const PendingAnswersScreen({super.key});

  @override
  ConsumerState<PendingAnswersScreen> createState() => _PendingAnswersScreenState();
}

class _PendingAnswersScreenState extends ConsumerState<PendingAnswersScreen> {
  bool _busy = false;

  /// [id] = uma resposta; sem ele, todas.
  Future<void> _act({String? id, required bool accept}) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    setState(() => _busy = true);
    final path = '/birthday-request/answers${id == null ? '' : '/$id'}/${accept ? 'accept' : 'ignore'}';
    await runGuarded(
      context,
      () => api.post(path),
      success: id != null ? null : (accept ? 'Aniversários acrescentados à tua lista.' : 'Respostas ignoradas.'),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(pendingAnswersProvider);
    ref.invalidate(birthdayRequestProvider);
    if (accept) ref.read(dataRepositoryProvider)?.load().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final answers = ref.watch(pendingAnswersProvider);
    final muted = context.palette.mutedForeground;
    final list = answers.value ?? const <PendingAnswer>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Por confirmar'),
        actions: [
          if (list.length > 1)
            TextButton(onPressed: _busy ? null : () => _act(accept: true), child: const Text('Aceitar todos')),
          const SizedBox(width: 8),
        ],
      ),
      body: answers.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(pendingAnswersProvider)),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: LucideIcons.inbox,
                title: 'Nada por confirmar',
                message: 'Quando alguém deixar a data pelo teu link, aparece aqui para a aceitares.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      'Só entram na tua lista os que aceitares. Ignora os que não conheces.',
                      style: context.text.bodyMedium?.copyWith(color: muted),
                    ),
                  ),
                  for (final a in list)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: context.palette.accent,
                        child: Text(initialOf(a.name), style: TextStyle(color: context.palette.accentForeground)),
                      ),
                      title: Text(a.name),
                      subtitle: Text(Fmt.birthDate(a.day, a.month, a.year), style: TextStyle(color: muted)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Ignorar',
                            onPressed: _busy ? null : () => _act(id: a.id, accept: false),
                            icon: Icon(LucideIcons.x, color: muted),
                          ),
                          IconButton(
                            tooltip: 'Aceitar',
                            onPressed: _busy ? null : () => _act(id: a.id, accept: true),
                            icon: Icon(LucideIcons.check, color: context.colors.primary),
                          ),
                        ],
                      ),
                    ),
                  if (list.length > 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: TextButton(
                        onPressed: _busy ? null : () => _act(accept: false),
                        child: const Text('Ignorar todos'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
