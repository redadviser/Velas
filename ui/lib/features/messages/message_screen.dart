import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/cards_providers.dart';
import '../../core/chat_providers.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import '../../data/models/models.dart';
import '../../data/repositories/cards_repository.dart';
import '../../services/message_suggestions.dart';
import '../cards/card_links.dart';
import '../people/linked_friend.dart';

enum _SendAs { card, wall, text }

/// Escrever, guardar e enviar a mensagem de parabéns (RF14) com sugestões (RF15).
/// Com servidor, a mensagem pode ir como cartão: um link que a pessoa abre com
/// ou sem a app e que, na app, lhe permite responder; ou, se a pessoa já for
/// amiga na Birthdayly, diretamente para o mural dela (ver features/cards).
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

  Future<void> _share(Person person) async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    if (_dirty) await _save(quiet: true);
    final cards = ref.read(cardsRepositoryProvider);
    if (cards == null) {
      await SharePlus.instance.share(ShareParams(text: body));
      return;
    }
    final friends = await _friends();
    if (!mounted) return;
    // O amigo ligado ao aniversário; sem ligação, o que tiver o mesmo nome.
    final linked = friends.where((f) => f.userId == person.linkedUserId).firstOrNull;
    final match = linked ?? matchingFriend(person.name, friends);
    final choice = await _chooseFormat(person, hasFriends: friends.isNotEmpty, match: match);
    if (choice == null || !mounted) return;
    switch (choice) {
      case _SendAs.text:
        await SharePlus.instance.share(ShareParams(text: body));
      case _SendAs.card:
        await _sendCard(cards, person, body);
      case _SendAs.wall:
        final friend = match ?? await pickFriend(context, friends, title: 'No mural de quem?');
        if (friend != null && mounted) await _postToWall(cards, person, friend, body);
    }
  }

  Future<List<ChatUser>> _friends() async {
    if (ref.read(chatRepositoryProvider) == null) return const [];
    try {
      return (await ref.read(friendsProvider.future)).friends;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _sendCard(CardsRepository cards, Person person, String body) async {
    // A mesma mensagem reenviada usa o mesmo cartão (não cria outro link).
    var card = ref.read(sentCardsProvider(person.id)).value?.where((c) => c.body == body && !c.onWall).firstOrNull;
    final ok = await runGuarded(context, () async {
      card ??= await cards.create(personId: person.id, recipientName: person.firstName, body: body);
    });
    if (!ok || card == null) return;
    ref.invalidate(sentCardsProvider(person.id));
    await SharePlus.instance.share(ShareParams(text: CardLinks.shareMessage(person.firstName, card!.token)));
  }

  Future<void> _postToWall(CardsRepository cards, Person person, ChatUser friend, String body) async {
    final already = ref.read(sentCardsProvider(person.id)).value?.any((c) => c.body == body && c.onWall) ?? false;
    if (already) {
      showMessage(context, 'Esta mensagem já está no mural de ${friend.firstName}.');
      return;
    }
    final ok = await runGuarded(
      context,
      () => cards.create(personId: person.id, recipientName: person.firstName, body: body, friendId: friend.userId),
      success: 'Publicado no mural de ${friend.firstName} 🎉',
    );
    if (!ok) return;
    ref.invalidate(sentCardsProvider(person.id));
    // O servidor liga o aniversário a este amigo (se ainda não estava ligado).
    if (person.linkedUserId == null) ref.read(dataRepositoryProvider)?.load().catchError((_) {});
  }

  /// Com um amigo que é esta pessoa ([match]), o mural é a opção recomendada.
  Future<_SendAs?> _chooseFormat(Person person, {required bool hasFriends, ChatUser? match}) =>
      showModalBottomSheet<_SendAs>(
        context: context,
        builder: (ctx) {
          Widget title(String text, {bool recommended = false}) => Row(
            children: [
              Flexible(child: Text(text)),
              if (recommended) ...[const SizedBox(width: 8), const Pill(label: 'Recomendado', dense: true)],
            ],
          );
          final wall = ListTile(
            leading: const Icon(LucideIcons.partyPopper),
            title: title(match != null ? 'No mural de ${match.firstName}' : 'No mural de um amigo', recommended: match != null),
            subtitle: Text(
              match != null
                  ? '${match.firstName} já está na Birthdayly: a mensagem chega logo ao mural e à vossa conversa.'
                  : 'Para amigos que já estão na Birthdayly: a mensagem chega logo ao mural.',
            ),
            onTap: () => Navigator.pop(ctx, _SendAs.wall),
          );
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Como queres enviar?', style: AppTheme.display(ctx, size: 22)),
                ),
                if (match != null) wall,
                ListTile(
                  leading: const Icon(LucideIcons.mailOpen),
                  title: title('Cartão de parabéns', recommended: match == null),
                  subtitle: Text(
                    '${person.firstName} abre a tua mensagem num cartão, mesmo sem a app, e pode responder-te na Birthdayly.',
                  ),
                  onTap: () => Navigator.pop(ctx, _SendAs.card),
                ),
                if (match == null && hasFriends) wall,
                ListTile(
                  leading: const Icon(LucideIcons.messageSquareText),
                  title: const Text('Só o texto'),
                  subtitle: const Text('Envia a mensagem como texto normal.'),
                  onTap: () => Navigator.pop(ctx, _SendAs.text),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );

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
                    onPressed: _text.text.trim().isEmpty ? null : () => _share(person),
                    icon: const Icon(LucideIcons.send, size: 18),
                    label: const Text('Enviar'),
                  ),
                ),
              ],
            ),
            _CardStatus(personId: person.id, firstName: person.firstName),
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

/// Estado do último cartão enviado a esta pessoa.
class _CardStatus extends ConsumerWidget {
  const _CardStatus({required this.personId, required this.firstName});

  final String personId;
  final String firstName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(sentCardsProvider(personId)).value?.firstOrNull;
    if (card == null) return const SizedBox.shrink();
    final (icon, text, highlight) = card.onWall
        ? card.openedAt != null
              ? (LucideIcons.checkCheck, '$firstName viu a tua mensagem no mural 🎉', true)
              : (LucideIcons.partyPopper, 'Publicado no mural de $firstName', false)
        : card.claimedAt != null
        ? (LucideIcons.checkCheck, '$firstName guardou o teu cartão e pode responder-te na app 🎉', true)
        : card.openedAt != null
        ? (LucideIcons.eye, '$firstName abriu o teu cartão', false)
        : (LucideIcons.send, 'Cartão enviado. Ainda não foi aberto.', false);
    final color = highlight ? context.colors.primary : context.palette.mutedForeground;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: context.text.bodySmall?.copyWith(color: color))),
        ],
      ),
    );
  }
}
