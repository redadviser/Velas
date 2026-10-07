import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/birthday_widgets.dart';
import '../../core/widgets/common.dart';
import '../../data/models/group_models.dart';
import '../../data/models/models.dart';
import '../auth/auth_widgets.dart';
import 'invite_widgets.dart';
import 'payment_widgets.dart';

double? parseEuros(String text) {
  final t = text.trim().replaceAll(' ', '').replaceAll(',', '.');
  return t.isEmpty ? null : double.tryParse(t);
}

String formatEuros(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2).replaceAll('.', ',');

class _Draft {
  _Draft({
    required this.id,
    required this.name,
    this.userId,
    this.username = '',
    this.original,
    double? amount,
    this.payment = PaymentDetails.empty,
  }) : amount = TextEditingController(text: amount == null ? '' : formatEuros(amount));

  final String id;
  String name;
  final String? userId;
  final String username;
  final GroupMember? original;
  final TextEditingController amount;
  PaymentDetails payment;

  bool get isNew => original == null;
}

class GroupFormScreen extends ConsumerStatefulWidget {
  const GroupFormScreen({super.key, this.groupId, this.personId});

  final String? groupId;
  final String? personId;

  @override
  ConsumerState<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends ConsumerState<GroupFormScreen> {
  final _form = GlobalKey<FormState>();
  final _uuid = const Uuid();
  final _title = TextEditingController();
  final _celebrant = TextEditingController();
  final _gift = TextEditingController();
  final _link = TextEditingController();
  final _total = TextEditingController();

  GiftGroup? _original;
  Person? _person;
  int? _day;
  int? _month;
  DateTime? _deadline;
  SplitMode _split = SplitMode.equal;
  final List<_Draft> _members = [];
  final List<_Draft> _removed = [];
  String? _buyerId;
  final List<FoundUser> _toInvite = [];
  bool _saving = false;
  bool _titleTouched = false;

  bool get _isEdit => widget.groupId != null;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider)!;
    final group = widget.groupId == null
        ? null
        : ref.read(groupsProvider).value?.where((g) => g.id == widget.groupId).firstOrNull;

    if (group != null) {
      _original = group;
      _titleTouched = true;
      _title.text = group.title;
      _celebrant.text = group.celebrantName;
      _gift.text = group.giftDescription;
      _link.text = group.giftLink;
      _total.text = formatEuros(group.targetAmount);
      _day = group.celebrantDay;
      _month = group.celebrantMonth;
      _deadline = group.deadline;
      _split = group.splitMode;
      _buyerId = group.buyerMemberId;
      _person = group.personId == null ? null : ref.read(dataProvider).person(group.personId!);
      for (final m in group.sortedMembers) {
        _members.add(
          _Draft(id: m.id, name: m.name, userId: m.userId, username: m.username, original: m, amount: m.customAmount, payment: m.payment),
        );
      }
    } else {
      _members.add(_Draft(id: _uuid.v4(), name: user.name, userId: user.id, username: user.username));
      final p = widget.personId == null ? null : ref.read(dataProvider).person(widget.personId!);
      if (p != null) _selectPerson(p);
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _celebrant, _gift, _link, _total]) {
      c.dispose();
    }
    for (final m in [..._members, ..._removed]) {
      m.amount.dispose();
    }
    super.dispose();
  }

  void _selectPerson(Person p) {
    _person = p;
    _celebrant.text = p.name;
    _day = p.day;
    _month = p.month;
    if (!_titleTouched) _title.text = 'Prenda para ${p.firstName}';
    _deadline ??= BirthdayUtils.addDays(p.nextBirthday(), -1);
    final idea = ref.read(dataProvider).giftsFor(p.id).where((g) => !g.purchased).firstOrNull;
    if (_gift.text.isEmpty && idea != null) {
      _gift.text = idea.title;
      if (idea.price != null && _total.text.isEmpty) _total.text = formatEuros(idea.price!);
      if (_link.text.isEmpty) _link.text = idea.link;
    }
  }

  Future<void> _pickPerson() async {
    final data = ref.read(dataProvider);
    final p = await showModalBottomSheet<Person>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Para quem é a prenda?', style: AppTheme.display(ctx, size: 22)),
            ),
            if (data.people.isEmpty)
              const Padding(padding: EdgeInsets.all(20), child: Text('Ainda não tens pessoas na tua lista.')),
            for (final p in data.upcoming) PersonTile(person: p, data: data, onTap: () => Navigator.pop(ctx, p)),
          ],
        ),
      ),
    );
    if (p != null) setState(() => _selectPerson(p));
  }

  Future<void> _pickDeadline() async {
    final now = BirthdayUtils.today();
    final d = await showDatePicker(
      context: context,
      initialDate: _deadline != null && !_deadline!.isBefore(now) ? _deadline! : now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      helpText: 'Pagar até',
    );
    if (d != null) setState(() => _deadline = d);
  }

  Future<void> _removeMember(_Draft m) async {
    if (m.original?.status != null && m.original!.status != ContributionStatus.pending) {
      final ok = await confirmDialog(
        context,
        title: 'Remover ${m.name}?',
        message: '${m.name} já registou o pagamento. Se remover, esse registo perde-se.',
        confirm: 'Remover',
      );
      if (!ok) return;
    }
    setState(() {
      _members.remove(m);
      if (!m.isNew) _removed.add(m);
      if (_buyerId == m.id) _buyerId = null;
    });
  }

  double get _customSum => _members.fold(0, (a, m) => a + (parseEuros(m.amount.text) ?? 0));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final total = parseEuros(_total.text)!;
    if (_split == SplitMode.custom && ((_customSum - total).abs() >= 0.01)) {
      showMessage(
        context,
        'A soma das partes (${Fmt.money(_customSum)}) tem de ser igual ao total (${Fmt.money(total)}).',
      );
      return;
    }
    final buyer = _members.where((m) => m.id == _buyerId).firstOrNull;
    if (buyer != null && buyer.userId == null && !buyer.payment.hasAnyDigital && !buyer.payment.acceptsCash) {
      showMessage(context, 'Indica como se paga a ${buyer.name}.');
      return;
    }

    final user = ref.read(currentUserProvider)!;
    final now = DateTime.now();
    final base =
        _original ??
        GiftGroup(
          id: _uuid.v4(),
          createdBy: user.id,
          title: '',
          celebrantName: '',
          targetAmount: total,
          createdAt: now,
        );
    final group = base.copyWith(
      title: _title.text.trim(),
      celebrantName: _celebrant.text.trim(),
      celebrantDay: () => _day,
      celebrantMonth: () => _month,
      personId: () => _person?.id,
      giftDescription: _gift.text.trim(),
      giftLink: _link.text.trim(),
      targetAmount: total,
      splitMode: _split,
      buyerMemberId: () => _buyerId,
      deadline: () => _deadline,
    );

    GroupMember toMember(_Draft d) =>
        (d.original ?? GroupMember(id: d.id, groupId: group.id, name: d.name, userId: d.userId, username: d.username, createdAt: now))
            .copyWith(
              name: d.name,
              customAmount: () => _split == SplitMode.custom ? parseEuros(d.amount.text) : null,
              payment: d.payment,
            );

    final newMembers = _members.where((d) => d.isNew).map(toMember).toList();
    final changed = _members.where((d) => !d.isNew).map(toMember).where((m) {
      final o = _members.firstWhere((d) => d.id == m.id).original!;
      return o.name != m.name ||
          o.customAmount != m.customAmount ||
          o.payment.toJson().toString() != m.payment.toJson().toString();
    }).toList();
    final optimistic = group.copyWith(members: [for (final d in _members) toMember(d)]);

    setState(() => _saving = true);
    final ok = await runGuarded(
      context,
      () => ref.read(groupsProvider.notifier).mutate((repo) async {
        for (final r in _removed) {
          await repo.removeMember(r.original!);
        }
        await repo.saveGroup(group.copyWith(members: const []), newMembers: newMembers);
        for (final m in changed) {
          await repo.updateMemberInfo(m);
        }
        for (final u in _toInvite) {
          await repo.inviteUser(group.id, u.userId);
        }
      }, optimistic: optimistic),
      success: [
        _isEdit ? 'Grupo atualizado.' : 'Grupo criado.',
        if (_toInvite.isNotEmpty) _toInvite.length == 1 ? 'Convite enviado.' : '${_toInvite.length} convites enviados.',
      ].join(' '),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    if (_isEdit) {
      context.pop();
    } else {
      context.pushReplacement('/groups/${group.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider)!;
    final total = parseEuros(_total.text);
    final buyerDraft = _members.where((m) => m.id == _buyerId).firstOrNull;
    final equalShare = total == null || _members.isEmpty ? null : total / _members.length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(LucideIcons.x), onPressed: () => context.pop()),
        title: Text(_isEdit ? 'Editar grupo' : 'Prenda em grupo'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
              child: _saving
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEdit ? 'Guardar' : 'Criar'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          children: [
            const FieldLabel('Para quem é?'),
            TextFormField(
              controller: _celebrant,
              textCapitalization: TextCapitalization.words,
              validator: (v) => Validators.required(v, 'Indica para quem é a prenda.'),
              onChanged: (v) => setState(() {
                if (_person != null && v != _person!.name) _person = null;
                if (!_titleTouched && v.trim().isNotEmpty) _title.text = 'Prenda para ${v.trim().split(' ').first}';
              }),
              decoration: InputDecoration(
                hintText: 'Nome',
                prefixIcon: const Icon(LucideIcons.cake, size: 18),
                suffixIcon: TextButton(onPressed: _pickPerson, child: const Text('Da lista')),
              ),
            ),
            if (_day != null && _month != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  'Faz anos a ${Fmt.dayMonth(DateTime(2000, _month!, _day!))}',
                  style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                ),
              ),
            const SizedBox(height: 18),
            const FieldLabel('Nome do grupo'),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => _titleTouched = true,
              validator: (v) => Validators.required(v, 'Dá um nome ao grupo.'),
              decoration: const InputDecoration(hintText: 'Ex.: Prenda para a Mãe'),
            ),
            const SizedBox(height: 18),
            const FieldLabel('A prenda'),
            TextFormField(
              controller: _gift,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'O que vão oferecer? (pode ficar para depois)'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _link,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'Link (opcional)',
                prefixIcon: Icon(LucideIcons.link, size: 16),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FieldLabel('Valor total'),
                      TextFormField(
                        controller: _total,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          final n = parseEuros(v ?? '');
                          return n == null || n <= 0 ? 'Indica o valor.' : null;
                        },
                        decoration: const InputDecoration(hintText: '0', suffixText: '€'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FieldLabel('Pagar até'),
                      OutlinedButton.icon(
                        onPressed: _pickDeadline,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          alignment: Alignment.centerLeft,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(LucideIcons.calendar, size: 16),
                        label: Text(_deadline == null ? 'Sem data' : Fmt.dayMonth(_deadline!)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text('Participantes', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Adiciona pelo @username, email ou telemóvel — são únicos, por isso não há confusão com nomes '
              'repetidos. Cada pessoa entra no grupo quando aceitar o convite.',
              style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
            ),
            const SizedBox(height: 12),
            ContactLookup(
              actionLabel: 'Adicionar',
              onAction: (u) async {
                final already =
                    _toInvite.any((x) => x.userId == u.userId) || _members.any((m) => m.userId == u.userId);
                if (already) return '${u.name} já está na lista.';
                setState(() => _toInvite.add(u));
                return '${u.name} recebe o convite quando ${_isEdit ? 'guardares' : 'criares o grupo'}.';
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<SplitMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: SplitMode.equal, label: Text('Dividir igual')),
                  ButtonSegment(value: SplitMode.custom, label: Text('Valores à medida')),
                ],
                selected: {_split},
                onSelectionChanged: (s) => setState(() => _split = s.first),
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, m) in _members.indexed) ...[
                    if (i > 0) const Divider(indent: 16, endIndent: 16),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: swatch(i).withValues(alpha: 0.16),
                            child: Text(
                              m.name.isEmpty ? '?' : m.name[0].toUpperCase(),
                              style: TextStyle(color: swatch(i), fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.userId == user.id ? '${m.name} (tu)' : m.name, style: context.text.bodyLarge),
                                Text(
                                  [
                                    if (m.username.isNotEmpty) '@${m.username}',
                                    if (m.userId == (_original?.createdBy ?? user.id)) 'Administrador',
                                    if (m.userId == null) 'Sem conta',
                                  ].join(' · '),
                                  style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                                ),
                              ],
                            ),
                          ),
                          if (_split == SplitMode.custom)
                            SizedBox(
                              width: 92,
                              child: TextFormField(
                                controller: m.amount,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                                onChanged: (_) => setState(() {}),
                                textAlign: TextAlign.right,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: '0',
                                  suffixText: '€',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                ),
                              ),
                            )
                          else if (equalShare != null)
                            Text(Fmt.money(equalShare), style: context.text.labelLarge),
                          if (m.userId != (_original?.createdBy ?? user.id))
                            IconButton(
                              tooltip: 'Remover',
                              onPressed: () => _removeMember(m),
                              icon: Icon(LucideIcons.x, size: 18, color: context.palette.mutedForeground),
                            )
                          else
                            const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  ],
                  for (final u in _toInvite) ...[
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: context.palette.muted,
                        child: Icon(LucideIcons.mail, size: 14, color: context.palette.mutedForeground),
                      ),
                      title: Text(u.name),
                      subtitle: Text(
                        [if (u.username.isNotEmpty) '@${u.username}', 'Recebe o convite ao guardar'].join(' · '),
                      ),
                      trailing: IconButton(
                        tooltip: 'Remover',
                        icon: Icon(LucideIcons.x, size: 18, color: context.palette.mutedForeground),
                        onPressed: () => setState(() => _toInvite.remove(u)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_split == SplitMode.custom && total != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Builder(
                  builder: (context) {
                    final diff = total - _customSum;
                    final ok = diff.abs() < 0.01;
                    return Text(
                      ok
                          ? 'As partes somam o total.'
                          : diff > 0
                          ? 'Faltam distribuir ${Fmt.money(diff)}.'
                          : 'As partes excedem o total em ${Fmt.money(-diff)}.',
                      style: context.text.bodySmall?.copyWith(
                        color: ok ? context.palette.success : context.colors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 28),
            Text('Quem compra a prenda?', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Recebe o dinheiro dos outros. Se não escolheres ninguém, és tu, como administrador.',
              style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _members)
                  ChoiceChip(
                    avatar: Icon(LucideIcons.shoppingBag, size: 14, color: context.palette.accentForeground),
                    label: Text(m.userId == user.id ? 'Eu' : m.name),
                    selected:
                        (_buyerId ?? _members.firstWhere((d) => d.userId == (_original?.createdBy ?? user.id)).id) ==
                        m.id,
                    onSelected: (_) =>
                        setState(() => _buyerId = m.userId == (_original?.createdBy ?? user.id) ? null : m.id),
                  ),
              ],
            ),
            if (buyerDraft != null && buyerDraft.userId == null) ...[
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Como se paga a ${buyerDraft.name}?', style: context.text.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      '${buyerDraft.name} não tem conta, por isso indica tu os dados.',
                      style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
                    ),
                    const SizedBox(height: 16),
                    PaymentDetailsFields(
                      key: ValueKey(buyerDraft.id),
                      initial: buyerDraft.payment,
                      onChanged: (d) => buyerDraft.payment = d,
                    ),
                  ],
                ),
              ),
            ] else if ((buyerDraft == null || buyerDraft.userId == user.id) && !user.payment.hasAnyDigital) ...[
              const SizedBox(height: 16),
              AppCard(
                color: context.palette.accent,
                onTap: () => context.push('/profile/payments'),
                child: Row(
                  children: [
                    Icon(LucideIcons.wallet, color: context.palette.accentForeground, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Adiciona o teu MB WAY ou IBAN para os outros te pagarem.',
                        style: TextStyle(color: context.palette.accentForeground, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(LucideIcons.chevronRight, color: context.palette.accentForeground, size: 18),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
