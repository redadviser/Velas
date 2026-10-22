import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/chat_providers.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import 'chat_widgets.dart';

/// Motivos de denúncia (iguais aos do servidor, modules/safety).
const reportReasons = [
  ('spam', 'Spam ou publicidade'),
  ('harassment', 'Assédio ou ameaças'),
  ('inappropriate', 'Conteúdo impróprio'),
  ('impersonation', 'Perfil falso ou a fazer-se passar por outra pessoa'),
  ('underage', 'Parece ser menor de idade'),
  ('other', 'Outro motivo'),
];

/// Bloquear, com a confirmação do que acontece. `true` se bloqueou.
Future<bool> confirmBlock(BuildContext context, WidgetRef ref, ChatUser user) async {
  final ok = await confirmDialog(
    context,
    title: 'Bloquear ${user.firstName}?',
    message:
        'Deixam de ser amigos, ${user.firstName} não te pode enviar mensagens nem pedidos de amizade, '
        'e deixas de ver as mensagens desta pessoa nos grupos. Não recebe nenhum aviso.',
    confirm: 'Bloquear',
  );
  if (!ok || !context.mounted) return false;
  return runGuarded(
    context,
    () => ref.read(blockedUsersProvider.notifier).block(user),
    success: 'Bloqueaste ${user.firstName}.',
  );
}

/// Denunciar um utilizador ou, com [messageId], uma mensagem dele.
Future<void> showReportSheet(BuildContext context, WidgetRef ref, ChatUser user, {String? messageId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReportSheet(user: user, messageId: messageId),
  );
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.user, this.messageId});

  final ChatUser user;
  final String? messageId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  String? _reason;
  bool _block = true;
  bool _sending = false;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final api = ref.read(apiClientProvider);
    if (api == null || _reason == null) return;
    setState(() => _sending = true);
    final ok = await runGuarded(context, () async {
      await api.post('/users/${widget.user.userId}/report', {
        'reason': _reason,
        'details': _details.text.trim(),
        'message_id': ?widget.messageId,
        'block': _block,
      });
      if (_block) {
        ref.invalidate(blockedUsersProvider);
        ref.invalidate(friendsProvider);
        ref.invalidate(conversationsProvider);
      }
    }, success: 'Obrigado. A equipa da Birthdayly vai analisar a denúncia.');
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.mutedForeground;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.messageId == null ? 'Denunciar ${widget.user.firstName}' : 'Denunciar mensagem',
                style: AppTheme.display(context, size: 22),
              ),
              const SizedBox(height: 4),
              Text('A denúncia é anónima: ${widget.user.firstName} não fica a saber.', style: TextStyle(color: muted)),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v),
                child: Column(
                  children: [
                    for (final (value, label) in reportReasons)
                      RadioListTile<String>(value: value, title: Text(label), contentPadding: EdgeInsets.zero, dense: true),
                  ],
                ),
              ),
              TextField(
                controller: _details,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Queres explicar melhor? (opcional)'),
              ),
              CheckboxListTile(
                value: _block,
                onChanged: (v) => setState(() => _block = v ?? false),
                contentPadding: EdgeInsets.zero,
                title: Text('Bloquear ${widget.user.firstName} também'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: context.colors.error),
                onPressed: _reason == null || _sending ? null : _send,
                child: _sending
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                    : const Text('Enviar denúncia'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Os utilizadores que bloqueei, para os desbloquear.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedUsersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bloqueados')),
      body: blocked.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        error: (e, _) => ErrorRetry(error: e, onRetry: () => ref.invalidate(blockedUsersProvider)),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: LucideIcons.shieldCheck,
                title: 'Ninguém bloqueado',
                message: 'Quem bloqueares aparece aqui. Bloqueia a partir do perfil de alguém ou de uma mensagem.',
              )
            : ListView(
                children: [
                  for (final u in list)
                    ListTile(
                      leading: UserAvatar(user: u, size: 40),
                      title: Text(u.name),
                      subtitle: u.username.isEmpty ? null : Text('@${u.username}'),
                      trailing: TextButton(
                        onPressed: () => runGuarded(
                          context,
                          () => ref.read(blockedUsersProvider.notifier).unblock(u.userId),
                          success: 'Desbloqueaste ${u.firstName}.',
                        ),
                        child: const Text('Desbloquear'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
