import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../services/message_suggestions.dart';

/// Escrever, guardar e enviar a mensagem de parabéns (RF14) com sugestões (RF15).
class MessageScreen extends ConsumerStatefulWidget {
  const MessageScreen({super.key, required this.personId});

  final String personId;

  @override
  ConsumerState<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends ConsumerState<MessageScreen> {
  final _text = TextEditingController();
  BirthdayMessage? _existing;
  MessageTone _tone = MessageTone.warm;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _existing = ref.read(dataProvider).messageFor(widget.personId);
    _text.text = _existing?.body ?? '';
    _tone = MessageTone.values.firstWhere((t) => t.label == _existing?.tone, orElse: () => MessageTone.warm);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _dirty => _text.text.trim() != (_existing?.body ?? '');

  Future<bool> _save({bool quiet = false}) async {
    final repo = ref.read(dataRepositoryProvider)!;
    final body = _text.text.trim();
    setState(() => _saving = true);
    final ok = await runGuarded(context, () async {
      if (body.isEmpty) {
        if (_existing != null) await repo.deleteMessage(_existing!.id);
        _existing = null;
        return;
      }
      final msg =
          (_existing ??
                  BirthdayMessage(
                    id: const Uuid().v4(),
                    personId: widget.personId,
                    body: body,
                    updatedAt: DateTime.now(),
                  ))
              .copyWith(body: body, tone: _tone.label);
      await repo.saveMessage(msg);
      _existing = msg;
    }, success: quiet ? null : (body.isEmpty ? 'Mensagem removida.' : 'Mensagem guardada.'));
    if (mounted) setState(() => _saving = false);
    return ok;
  }

  Future<void> _share() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    if (_dirty) await _save(quiet: true);
    await SharePlus.instance.share(ShareParams(text: body));
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final person = data.person(widget.personId);
    if (person == null) return Scaffold(appBar: AppBar());
    final suggestions = MessageSuggestions.generate(person, _tone);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await confirmDialog(
          context,
          title: 'Descartar alterações?',
          message: 'A mensagem ainda não foi guardada.',
          confirm: 'Descartar',
        );
        if (discard && context.mounted) {
          _text.text = _existing?.body ?? '';
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              PersonAvatar(person: person, color: personColor(person, data), size: 32),
              const SizedBox(width: 10),
              Expanded(child: Text('Para ${person.firstName}', overflow: TextOverflow.ellipsis)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _saving || !_dirty
                  ? null
                  : () async {
                      if (await _save() && context.mounted) context.pop();
                    },
              child: const Text('Guardar'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _text,
                minLines: 5,
                maxLines: 12,
                maxLength: 1000,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.sentences,
                style: AppTheme.display(context, size: 17).copyWith(fontWeight: FontWeight.w400, height: 1.5),
                decoration: const InputDecoration(
                  hintText: 'Escreve aqui os teus parabéns…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _text.text.trim().isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: _text.text.trim()));
                            if (context.mounted) showMessage(context, 'Mensagem copiada.');
                          },
                    icon: const Icon(LucideIcons.copy, size: 18),
                    label: const Text('Copiar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _text.text.trim().isEmpty ? null : _share,
                    icon: const Icon(LucideIcons.send, size: 18),
                    label: const Text('Enviar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Icon(LucideIcons.sparkles, size: 18, color: context.colors.primary),
                const SizedBox(width: 8),
                Text('Sugestões', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final t in MessageTone.values)
                  ChoiceChip(label: Text(t.label), selected: _tone == t, onSelected: (_) => setState(() => _tone = t)),
              ],
            ),
            const SizedBox(height: 12),
            for (final s in suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => setState(() => _text.text = s),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(s, style: context.text.bodyMedium)),
                      const SizedBox(width: 12),
                      Icon(LucideIcons.cornerDownLeft, size: 16, color: context.palette.mutedForeground),
                    ],
                  ),
                ),
              ),
            Text(
              'Toca numa sugestão para a usar e depois personaliza-a à tua maneira.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
