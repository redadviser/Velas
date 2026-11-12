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
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import '../../data/models/models.dart';
import '../../data/repositories/cards_repository.dart';
import '../../services/message_suggestions.dart';
import '../../services/notification_service.dart';
import '../../data/models/card_models.dart';
import '../cards/card_links.dart';
import '../cards/card_media.dart';
import '../profile/plus.dart';
import '../people/linked_friend.dart';
import 'schedule_sheet.dart';
import '../../core/i18n/translations.dart';

enum _SendAs { card, wall, text }

/// Escrever, guardar e enviar a mensagem de parabéns (RF14) com sugestões (RF15).
/// Com servidor, a mensagem pode ir como cartão: um link que a pessoa abre com
/// ou sem a app e que, na app, lhe permite responder; ou, se a pessoa já for
/// amiga na Birthdayly, diretamente para o mural dela (ver features/cards).
class MessageScreen extends ConsumerStatefulWidget {
  const MessageScreen({super.key, required this.personId, this.autoSend = false});

  final String personId;

  /// Aberto pelo aviso de uma mensagem agendada: abre logo o "Como queres enviar?".
  final bool autoSend;

  @override
  ConsumerState<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends ConsumerState<MessageScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  int _suggestion = 0;
  BirthdayMessage? _existing;
  MessageTone _tone = MessageTone.warm;
  bool _saving = false;

  /// Cartão especial (Birthdayly+): a fotografia, o vídeo ou o áudio escolhido,
  /// e a chave dele no servidor depois de carregado (para não carregar duas vezes).
  PickedCardMedia? _media;
  String? _uploadedKey;

  Future<void> _attach(CardMediaKind kind) async {
    if (!await requirePlus(context, ref, feature: context.tr('Juntar uma fotografia, um vídeo ou um áudio'))) return;
    if (!mounted) return;
    final picked = await pickCardMedia(context, kind);
    if (picked == null || !mounted) return;
    setState(() {
      _media = picked;
      _uploadedKey = null;
    });
  }

  Future<String?> _mediaKey(CardsRepository cards) async {
    final m = _media;
    if (m == null) return null;
    return _uploadedKey ??= await cards.uploadMedia(m.bytes);
  }

  @override
  void initState() {
    super.initState();
    _existing = ref.read(dataProvider).messageFor(widget.personId);
    _text.text = _existing?.body ?? '';
    _tone = MessageTone.values.firstWhere((t) => t.label == _existing?.tone, orElse: () => MessageTone.warm);
    if (widget.autoSend) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final person = ref.read(dataProvider).person(widget.personId);
        if (mounted && person != null && _text.text.trim().isNotEmpty) _share(person);
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _dirty => _text.text.trim() != (_existing?.body ?? '');

  /// Guarda o texto (e, com [schedule], o agendamento; `() => null` cancela-o).
  Future<bool> _save({
    bool quiet = false,
    ({DateTime at, ScheduleVia via, String? friendId, String? mediaKey})? Function()? schedule,
    String? success,
  }) async {
    final repo = ref.read(dataRepositoryProvider)!;
    final body = _text.text.trim();
    // A versão mais recente (o servidor pode já a ter enviado entretanto).
    final current = ref.read(dataProvider).messageFor(widget.personId) ?? _existing;
    setState(() => _saving = true);
    final ok = await runGuarded(context, () async {
      if (body.isEmpty) {
        if (current != null) await repo.deleteMessage(current.id);
        _existing = null;
        return;
      }
      final msg =
          (current ??
                  BirthdayMessage(
                    id: const Uuid().v4(),
                    personId: widget.personId,
                    body: body,
                    updatedAt: DateTime.now(),
                  ))
              .copyWith(body: body, tone: _tone.label, schedule: schedule);
      await repo.saveMessage(msg);
      _existing = msg;
    }, success: quiet ? null : (success ?? (body.isEmpty ? tr('Mensagem removida.') : tr('Mensagem guardada.'))));
    if (mounted) setState(() => _saving = false);
    return ok;
  }

  /// Agendar: para o mural de um amigo (sai sozinha) ou um aviso para a enviar fora da app.
  Future<void> _schedule(Person person) async {
    if (_text.text.trim().isEmpty) return;
    final cards = ref.read(cardsRepositoryProvider);
    final friends = cards == null ? const <ChatUser>[] : await _friends();
    if (!mounted) return;
    final match =
        friends.where((f) => f.userId == person.linkedUserId).firstOrNull ?? matchingFriend(person.name, friends);
    final choice = await showScheduleSheet(
      context,
      person: person,
      friends: friends,
      match: match,
      current: ref.read(dataProvider).messageFor(person.id),
    );
    if (choice == null || !mounted) return;
    String? mediaKey;
    if (choice.via == ScheduleVia.wall && cards != null && _media != null) {
      final uploaded = await runGuarded(context, () async => mediaKey = await _mediaKey(cards));
      if (!uploaded || !mounted) return;
    }
    final ok = await _save(
      schedule: () => (at: choice.at, via: choice.via, friendId: choice.friend?.userId, mediaKey: mediaKey),
      success: tr('Agendada para {when}.', {'when': scheduleLabel(choice.at).toLowerCase()}),
    );
    // O aviso do "lembrar-me" é uma notificação deste telemóvel.
    if (ok && choice.via == ScheduleVia.remind) await NotificationService.instance.requestPermission();
  }

  Future<void> _cancelSchedule() => _save(schedule: () => null, success: tr('Agendamento cancelado.'));

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
        final friend = match ?? await pickFriend(context, friends, title: context.tr('No mural de quem?'));
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
    // A mesma mensagem reenviada (sem fotografia, vídeo ou áudio) usa o mesmo cartão.
    var card = _media != null
        ? null
        : ref
              .read(sentCardsProvider(person.id))
              .value
              ?.where((c) => c.body == body && !c.onWall && c.media == null)
              .firstOrNull;
    final ok = await runGuarded(context, () async {
      card ??= await cards.create(
        personId: person.id,
        recipientName: person.firstName,
        body: body,
        mediaKey: await _mediaKey(cards),
      );
    });
    if (!ok || card == null) return;
    ref.invalidate(sentCardsProvider(person.id));
    await SharePlus.instance.share(ShareParams(text: CardLinks.shareMessage(person.firstName, card!.token)));
  }

  Future<void> _postToWall(CardsRepository cards, Person person, ChatUser friend, String body) async {
    final already =
        _media == null &&
        (ref.read(sentCardsProvider(person.id)).value?.any((c) => c.body == body && c.onWall) ?? false);
    if (already) {
      showMessage(context, context.tr('Esta mensagem já está no mural de {name}.', {'name': friend.firstName}));
      return;
    }
    final ok = await runGuarded(
      context,
      () async => cards.create(
        personId: person.id,
        recipientName: person.firstName,
        body: body,
        friendId: friend.userId,
        mediaKey: await _mediaKey(cards),
      ),
      success: context.tr('Publicado no mural de {name} 🎉', {'name': friend.firstName}),
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
        isScrollControlled: true,
        builder: (ctx) {
          Widget title(String text, {bool recommended = false}) => Row(
            children: [
              Flexible(child: Text(text)),
              if (recommended) ...[const SizedBox(width: 8), Pill(label: ctx.tr('Recomendado'), dense: true)],
            ],
          );
          final wall = ListTile(
            leading: const Icon(LucideIcons.partyPopper),
            title: title(
              match != null ? ctx.tr('No mural de {name}', {'name': match.firstName}) : ctx.tr('No mural de um amigo'),
              recommended: match != null,
            ),
            subtitle: Text(
              match != null
                  ? ctx.tr('{name} já está na Birthdayly: a mensagem chega logo ao mural.', {'name': match.firstName})
                  : ctx.tr('Para amigos que já estão na Birthdayly: a mensagem chega logo ao mural.'),
            ),
            onTap: () => Navigator.pop(ctx, _SendAs.wall),
          );
          // Desliza quando não cabe (letra grande).
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(ctx.tr('Como queres enviar?'), style: AppTheme.display(ctx, size: 22)),
                  ),
                  if (match != null) wall,
                  ListTile(
                    leading: const Icon(LucideIcons.mailOpen),
                    title: title(ctx.tr('Cartão de parabéns'), recommended: match == null),
                    subtitle: Text(
                      ctx.tr(
                        '{name} abre a tua mensagem num cartão, mesmo sem a app, e pode responder-te na Birthdayly.',
                        {'name': person.firstName},
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, _SendAs.card),
                  ),
                  if (match == null && hasFriends) wall,
                  ListTile(
                    leading: const Icon(LucideIcons.messageSquareText),
                    title: Text(ctx.tr('Só o texto')),
                    subtitle: Text(ctx.tr('Envia a mensagem como texto normal.')),
                    onTap: () => Navigator.pop(ctx, _SendAs.text),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      );

  /// Troca o texto por uma sugestão do tom escolhido (a seguinte, em "Gerar outra").
  void _suggest(Person person, {bool next = false}) {
    final list = MessageSuggestions.generate(person, _tone);
    if (list.isEmpty) return;
    _suggestion = next ? (_suggestion + 1) % list.length : 0;
    setState(() => _text.text = list[_suggestion]);
  }

  /// Ao mudar de tom, só troca o texto se estiver vazio ou for uma sugestão por mexer.
  void _pickTone(Person person, MessageTone tone) {
    final current = _text.text.trim();
    final untouched =
        current.isEmpty || MessageTone.values.any((t) => MessageSuggestions.generate(person, t).contains(current));
    setState(() => _tone = tone);
    if (untouched) _suggest(person);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final person = data.person(widget.personId);
    if (person == null) return Scaffold(appBar: AppBar());
    final hasText = _text.text.trim().isNotEmpty;
    final muted = context.palette.mutedForeground;
    final scheduled = ref.watch(dataProvider).messageFor(person.id);
    final pending = scheduled != null && scheduled.isScheduled && scheduled.isPending;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await confirmDialog(
          context,
          title: context.tr('Descartar alterações?'),
          message: context.tr('A mensagem ainda não foi guardada.'),
          confirm: context.tr('Descartar'),
        );
        if (discard && context.mounted) {
          _text.text = _existing?.body ?? '';
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('Mensagem para {name}', {'name': person.firstName}), overflow: TextOverflow.ellipsis),
          actions: [
            TextButton(
              onPressed: _saving || !_dirty
                  ? null
                  : () async {
                      if (await _save() && context.mounted) context.pop();
                    },
              child: Text(context.tr('Guardar')),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.palette.accent,
                borderRadius: BorderRadius.circular(AppTheme.radius),
              ),
              child: Row(
                children: [
                  PersonAvatar(person: person, color: personColor(person, data), size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('Para {name}', {'name': person.firstName}),
                          style: AppTheme.display(context, size: 19),
                        ),
                        Text(
                          person.isToday
                              ? context.tr('Faz anos hoje')
                              : context.tr('Faz anos a {date}', {'date': Fmt.dayMonth(person.nextBirthday())}),
                          style: context.text.bodySmall?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(context.tr('QUE TOM QUERES?'), style: AppTheme.eyebrow(context)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in MessageTone.values)
                  ChoiceChip(label: Text(t.title), selected: _tone == t, onSelected: (_) => _pickTone(person, t)),
              ],
            ),
            const SizedBox(height: 20),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(LucideIcons.quote, size: 22, color: context.colors.primary),
                  ),
                  TextField(
                    controller: _text,
                    focusNode: _focus,
                    minLines: 4,
                    maxLines: 12,
                    maxLength: 1000,
                    onChanged: (_) => setState(() {}),
                    textCapitalization: TextCapitalization.sentences,
                    style: AppTheme.display(context, size: 17, weight: FontWeight.w500).copyWith(height: 1.5),
                    decoration: InputDecoration(
                      hintText: context.tr('Escolhe um tom ou escreve os teus parabéns…'),
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  const Divider(height: 20),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      IconButton(
                        tooltip: context.tr('Copiar'),
                        onPressed: !hasText
                            ? null
                            : () async {
                                await Clipboard.setData(ClipboardData(text: _text.text.trim()));
                                if (context.mounted) showMessage(context, context.tr('Mensagem copiada.'));
                              },
                        icon: const Icon(LucideIcons.copy, size: 18),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _focus.requestFocus(),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                        child: Text(context.tr('Editar')),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _suggest(person, next: hasText),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                        icon: const Icon(LucideIcons.sparkles, size: 18),
                        label: Text(hasText ? context.tr('Gerar outra') : context.tr('Gerar uma')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (ref.watch(cardsRepositoryProvider) != null) ...[
              const SizedBox(height: 28),
              Row(
                children: [
                  Flexible(child: Text(context.tr('Juntar algo especial'), style: AppTheme.display(context, size: 20))),
                  const SizedBox(width: 8),
                  const PlusBadge(),
                ],
              ),
              const SizedBox(height: 12),
              if (_media == null)
                Row(
                  children: [
                    for (final (kind, icon, label, hint) in [
                      (CardMediaKind.image, LucideIcons.camera, context.tr('Fotografia'), context.tr('Da galeria')),
                      (CardMediaKind.video, LucideIcons.video, context.tr('Vídeo'), context.tr('Da galeria')),
                      (CardMediaKind.audio, LucideIcons.mic, context.tr('Áudio'), context.tr('Gravar agora')),
                    ]) ...[
                      if (kind != CardMediaKind.image) const SizedBox(width: 10),
                      Expanded(
                        child: AppCard(
                          onTap: () => _attach(kind),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(icon, size: 22, color: context.colors.primary),
                              const SizedBox(height: 8),
                              Text(label, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(hint, style: context.text.bodySmall?.copyWith(color: muted), maxLines: 2),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CardMediaView(key: ValueKey(_media!.path), media: (kind: _media!.kind, url: _media!.path ?? '')),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => setState(() {
                          _media = null;
                          _uploadedKey = null;
                        }),
                        icon: const Icon(LucideIcons.x, size: 16),
                        label: Text(context.tr('Tirar')),
                      ),
                    ),
                  ],
                ),
            ],
            const SizedBox(height: 16),
            MergeSemantics(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.clock),
                title: Text(context.tr('Agendar')),
                subtitle: Text(
                  pending
                      ? (scheduled.scheduleVia == ScheduleVia.wall
                            ? context.tr('Vai para o mural: {when}', {
                                'when': scheduleLabel(scheduled.scheduledAt!).toLowerCase(),
                              })
                            : context.tr('Lembramos-te: {when}', {
                                'when': scheduleLabel(scheduled.scheduledAt!).toLowerCase(),
                              }))
                      : context.tr('Escolhe o dia e a hora, e nós tratamos do resto'),
                ),
                enabled: hasText || pending,
                onTap: _saving || !hasText ? null : () => _schedule(person),
                trailing: Switch(
                  value: pending,
                  onChanged: _saving || (!hasText && !pending)
                      ? null
                      : (on) => on ? _schedule(person) : _cancelSchedule(),
                ),
              ),
            ),
            _ScheduleStatus(personId: person.id, firstName: person.firstName),
            _CardStatus(personId: person.id, firstName: person.firstName),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.palette.border)),
            ),
            child: FilledButton.icon(
              onPressed: hasText ? () => _share(person) : null,
              icon: const Icon(LucideIcons.share2, size: 18),
              label: Text(context.tr('Enviar')),
            ),
          ),
        ),
      ),
    );
  }
}

/// A mensagem agendada: quando sai e como, se já saiu, ou porque falhou.
class _ScheduleStatus extends ConsumerWidget {
  const _ScheduleStatus({required this.personId, required this.firstName});

  final String personId;
  final String firstName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(dataProvider).messageFor(personId);
    if (m == null || !m.isScheduled) return const SizedBox.shrink();
    final when = scheduleLabel(m.scheduledAt!).toLowerCase();
    final friend = m.scheduleVia == ScheduleVia.wall
        ? ref.watch(friendsProvider).value?.friends.where((f) => f.userId == m.scheduleFriendId).firstOrNull?.firstName
        : null;
    final wallOf = friend ?? firstName;
    final (icon, text, error, pending) = switch (m) {
      _ when m.scheduleVia == ScheduleVia.wall && m.sendError != null => (
        LucideIcons.circleAlert,
        context.tr('Não foi possível publicar no mural de {name}. Envia-a de outra forma.', {'name': wallOf}),
        true,
        false,
      ),
      _ when m.scheduleVia == ScheduleVia.wall && m.sentAt != null => (
        LucideIcons.checkCheck,
        context.tr('Publicada no mural de {name} ({when}).', {'name': wallOf, 'when': when}),
        false,
        false,
      ),
      _ when m.scheduleVia == ScheduleVia.wall => (
        LucideIcons.calendarClock,
        context.tr('Vai para o mural de {name} {when}.', {'name': wallOf, 'when': when}),
        false,
        true,
      ),
      _ when m.isPending => (
        LucideIcons.bellRing,
        context.tr('Vamos lembrar-te de a enviar {when}.', {'when': when}),
        false,
        true,
      ),
      _ => (LucideIcons.bellRing, context.tr('Lembrete enviado {when}.', {'when': when}), false, false),
    };
    // Por enviar, a linha "Agendar" já diz quando.
    if (pending) return const SizedBox.shrink();
    final color = error
        ? context.colors.error
        : pending
        ? context.colors.primary
        : context.palette.mutedForeground;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: context.text.bodySmall?.copyWith(color: color)),
          ),
        ],
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
              ? (LucideIcons.checkCheck, context.tr('{name} viu a tua mensagem no mural 🎉', {'name': firstName}), true)
              : (LucideIcons.partyPopper, context.tr('Publicado no mural de {name}', {'name': firstName}), false)
        : card.claimedAt != null
        ? (
            LucideIcons.checkCheck,
            context.tr('{name} guardou o teu cartão e pode responder-te na app 🎉', {'name': firstName}),
            true,
          )
        : card.openedAt != null
        ? (LucideIcons.eye, context.tr('{name} abriu o teu cartão', {'name': firstName}), false)
        : (LucideIcons.send, context.tr('Cartão enviado. Ainda não foi aberto.'), false);
    final color = highlight ? context.colors.primary : context.palette.mutedForeground;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: context.text.bodySmall?.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
