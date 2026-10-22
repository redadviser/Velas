import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/models/chat_models.dart';
import '../../data/models/models.dart';
import '../people/linked_friend.dart';

/// O que se escolheu ao agendar: quando e como ([friend] só no mural).
typedef ScheduleChoice = ({DateTime at, ScheduleVia via, ChatUser? friend});

/// Por omissão: no próximo aniversário, às 9h. Se essa hora já passou (o
/// aniversário é hoje), daqui a uns minutos.
DateTime defaultScheduleTime(Person p, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final next = p.nextBirthday(DateTime(n.year, n.month, n.day));
  final at = DateTime(next.year, next.month, next.day, 9);
  if (at.isAfter(n.add(const Duration(minutes: 5)))) return at;
  final soon = n.add(const Duration(minutes: 20));
  return DateTime(soon.year, soon.month, soon.day, soon.hour, soon.minute - soon.minute % 5);
}

String _two(int v) => v.toString().padLeft(2, '0');

/// "Segunda-feira, 2 de março, às 09:00".
String scheduleLabel(DateTime at) => '${Fmt.weekdayDayMonth(at)}, às ${_two(at.hour)}:${_two(at.minute)}';

/// Agendar a mensagem para [person]. Com um amigo na Birthdayly ([friends] /
/// [match]), pode ir sozinha para o mural dele; senão (ou se se preferir), a
/// app lembra à hora marcada, com a mensagem pronta a enviar fora da app.
Future<ScheduleChoice?> showScheduleSheet(
  BuildContext context, {
  required Person person,
  required List<ChatUser> friends,
  ChatUser? match,
  BirthdayMessage? current,
}) => showModalBottomSheet<ScheduleChoice>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _ScheduleSheet(person: person, friends: friends, match: match, current: current),
);

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.person, required this.friends, this.match, this.current});

  final Person person;
  final List<ChatUser> friends;
  final ChatUser? match;
  final BirthdayMessage? current;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  late DateTime _at = widget.current?.isPending ?? false
      ? widget.current!.scheduledAt!
      : defaultScheduleTime(widget.person);
  late ChatUser? _friend =
      widget.friends.where((f) => f.userId == widget.current?.scheduleFriendId).firstOrNull ?? widget.match;
  late ScheduleVia _via = widget.current?.scheduleVia ?? (_friend != null ? ScheduleVia.wall : ScheduleVia.remind);

  bool get _past => !_at.isAfter(DateTime.now());

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _at.isBefore(now) ? now : _at,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 400)),
    );
    if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
  }

  Future<void> _chooseWall() async {
    if (_friend == null) {
      final f = await pickFriend(context, widget.friends, title: 'Para o mural de quem?');
      if (f == null || !mounted) return;
      setState(() => _friend = f);
    }
    setState(() => _via = ScheduleVia.wall);
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.mutedForeground;
    final first = widget.person.firstName;
    Widget option(ScheduleVia via, IconData icon, String title, String subtitle, VoidCallback onTap) {
      final selected = _via == via;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          onTap: onTap,
          color: selected ? context.palette.accent : null,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: selected ? context.colors.primary : muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleSmall),
                    const SizedBox(height: 2),
                    Text(subtitle, style: context.text.bodySmall?.copyWith(color: muted)),
                  ],
                ),
              ),
              Icon(
                selected ? LucideIcons.circleCheck : LucideIcons.circle,
                size: 20,
                color: selected ? context.colors.primary : muted,
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Agendar a mensagem', style: AppTheme.display(context, size: 22)),
            const SizedBox(height: 4),
            Text('Escreve agora e envia na hora certa.', style: context.text.bodyMedium?.copyWith(color: muted)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: _pickDate,
                    icon: const Icon(LucideIcons.calendarDays, size: 18),
                    label: Text(Fmt.dayMonth(_at), overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(110, 48)),
                  onPressed: _pickTime,
                  icon: const Icon(LucideIcons.clock, size: 18),
                  label: Text('${_two(_at.hour)}:${_two(_at.minute)}'),
                ),
              ],
            ),
            if (_past)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Escolhe uma hora no futuro.',
                  style: context.text.bodySmall?.copyWith(color: context.colors.error),
                ),
              ),
            const SizedBox(height: 16),
            if (widget.friends.isNotEmpty)
              option(
                ScheduleVia.wall,
                LucideIcons.partyPopper,
                _friend != null
                    ? 'Enviar sozinha para o mural de ${_friend!.firstName}'
                    : 'Enviar sozinha para o mural de um amigo',
                'Publicamos a mensagem à hora marcada, no mural e na vossa conversa. Avisamos-te quando for enviada.',
                _chooseWall,
              ),
            option(
              ScheduleVia.remind,
              LucideIcons.bellRing,
              'Lembrar-me de enviar',
              'Para WhatsApp, SMS ou cartão por link: à hora marcada avisamos-te com a mensagem pronta para $first.',
              () => setState(() => _via = ScheduleVia.remind),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _past || (_via == ScheduleVia.wall && _friend == null)
                  ? null
                  : () => Navigator.pop<ScheduleChoice>(context, (
                      at: _at,
                      via: _via,
                      friend: _via == ScheduleVia.wall ? _friend : null,
                    )),
              icon: const Icon(LucideIcons.calendarClock, size: 18),
              label: const Text('Agendar'),
            ),
          ],
        ),
      ),
    );
  }
}
