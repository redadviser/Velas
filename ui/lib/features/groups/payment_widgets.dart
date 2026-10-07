import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/models/payment.dart';
import '../auth/auth_widgets.dart';

IconData paymentIcon(PaymentMethod m) => switch (m) {
  PaymentMethod.mbway => LucideIcons.smartphone,
  PaymentMethod.transfer => LucideIcons.landmark,
  PaymentMethod.revolut => LucideIcons.creditCard,
  PaymentMethod.paypal => LucideIcons.wallet,
  PaymentMethod.cash => LucideIcons.banknote,
};

/// Campos editáveis dos dados de pagamento (perfil ou comprador sem conta).
class PaymentDetailsFields extends StatefulWidget {
  const PaymentDetailsFields({super.key, required this.initial, required this.onChanged});

  final PaymentDetails initial;
  final ValueChanged<PaymentDetails> onChanged;

  @override
  State<PaymentDetailsFields> createState() => _PaymentDetailsFieldsState();
}

class _PaymentDetailsFieldsState extends State<PaymentDetailsFields> {
  late final _phone = TextEditingController(text: PaymentFormat.displayPhone(widget.initial.mbwayPhone));
  late final _iban = TextEditingController(text: PaymentFormat.displayIban(widget.initial.iban));
  late final _holder = TextEditingController(text: widget.initial.ibanHolder);
  late final _revolut = TextEditingController(text: widget.initial.revolutTag);
  late final _paypal = TextEditingController(text: widget.initial.paypalUser);
  late bool _cash = widget.initial.acceptsCash;

  @override
  void dispose() {
    for (final c in [_phone, _iban, _holder, _revolut, _paypal]) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged(
    PaymentDetails(
      mbwayPhone: PaymentFormat.normalizePhone(_phone.text) ?? '',
      iban: PaymentFormat.normalizeIban(_iban.text) ?? '',
      ibanHolder: _holder.text.trim(),
      revolutTag: PaymentFormat.cleanHandle(_revolut.text),
      paypalUser: PaymentFormat.cleanHandle(_paypal.text),
      acceptsCash: _cash,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('MB WAY'),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
          onChanged: (_) => _emit(),
          validator: (v) => (v == null || v.trim().isEmpty || PaymentFormat.normalizePhone(v) != null)
              ? null
              : 'Número de telemóvel inválido.',
          decoration: const InputDecoration(
            hintText: '912 345 678',
            prefixIcon: Icon(LucideIcons.smartphone, size: 18),
          ),
        ),
        const SizedBox(height: 18),
        const FieldLabel('Transferência bancária'),
        TextFormField(
          controller: _iban,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => _emit(),
          validator: (v) => (v == null || v.trim().isEmpty || PaymentFormat.normalizeIban(v) != null)
              ? null
              : 'IBAN inválido. Confirma os dígitos.',
          decoration: const InputDecoration(
            hintText: 'PT50 0000 0000 0000 0000 0000 0',
            prefixIcon: Icon(LucideIcons.landmark, size: 18),
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _holder,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => _emit(),
          decoration: const InputDecoration(hintText: 'Nome do titular da conta'),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('Revolut'),
                  TextFormField(
                    controller: _revolut,
                    onChanged: (_) => _emit(),
                    decoration: const InputDecoration(hintText: '@utilizador'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('PayPal.me'),
                  TextFormField(
                    controller: _paypal,
                    onChanged: (_) => _emit(),
                    decoration: const InputDecoration(hintText: 'utilizador'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Aceito dinheiro em mão'),
          value: _cash,
          onChanged: (v) {
            setState(() => _cash = v);
            _emit();
          },
        ),
      ],
    );
  }
}

/// Ecrã "Pagar a …": mostra como pagar com cada método e permite marcar
/// "Já paguei". Devolve o método escolhido, ou `null` se cancelado.
Future<PaymentMethod?> showPaySheet(
  BuildContext context, {
  required String payeeName,
  required double amount,
  required PaymentDetails payee,
  required String reference,
}) {
  return showModalBottomSheet<PaymentMethod>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PaySheet(payeeName: payeeName, amount: amount, payee: payee, reference: reference),
  );
}

class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.payeeName, required this.amount, required this.payee, required this.reference});

  final String payeeName;
  final double amount;
  final PaymentDetails payee;
  final String reference;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  late PaymentMethod? _selected = widget.payee.methods.firstOrNull;

  String get _amountPlain => widget.amount.toStringAsFixed(2).replaceAll('.', ',');

  Future<void> _copy(String value, String what) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) showMessage(context, '$what copiado.');
  }

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showMessage(context, 'Não foi possível abrir o link.');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payee;
    final methods = p.methods;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              children: [
                Text(
                  'Pagar a ${widget.payeeName}',
                  style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(Fmt.money(widget.amount), style: AppTheme.display(context, size: 40)),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Copiar valor',
                      onPressed: () => _copy(_amountPlain, 'Valor'),
                      icon: Icon(LucideIcons.copy, size: 18, color: context.palette.mutedForeground),
                    ),
                  ],
                ),
                Text(widget.reference, style: TextStyle(color: context.palette.mutedForeground)),
                const SizedBox(height: 20),
                if (!p.hasAnyDigital)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      color: context.palette.muted,
                      child: Text(
                        '${widget.payeeName} ainda não adicionou MB WAY, IBAN ou outra forma de pagamento. '
                        'Podes pagar em mão ou pedir-lhe os dados.',
                        style: TextStyle(color: context.palette.mutedForeground),
                      ),
                    ),
                  ),
                for (final m in methods)
                  _MethodTile(
                    method: m,
                    selected: _selected == m,
                    onTap: () => setState(() => _selected = m),
                    child: switch (m) {
                      PaymentMethod.mbway => _Steps(
                        lines: const [
                          'Abre a app MB WAY ou a do teu banco.',
                          'Escolhe "Enviar dinheiro" e usa este número.',
                        ],
                        actions: [
                          _CopyRow(
                            label: 'Número',
                            value: PaymentFormat.displayPhone(p.mbwayPhone),
                            onCopy: () => _copy(p.mbwayPhone, 'Número'),
                          ),
                        ],
                      ),
                      PaymentMethod.transfer => _Steps(
                        lines: const ['Faz uma transferência a partir do teu banco.'],
                        actions: [
                          _CopyRow(
                            label: 'IBAN',
                            value: PaymentFormat.displayIban(p.iban),
                            onCopy: () => _copy(p.iban, 'IBAN'),
                          ),
                          if (p.ibanHolder.isNotEmpty)
                            _CopyRow(
                              label: 'Titular',
                              value: p.ibanHolder,
                              onCopy: () => _copy(p.ibanHolder, 'Titular'),
                            ),
                          _CopyRow(
                            label: 'Descritivo',
                            value: widget.reference,
                            onCopy: () => _copy(widget.reference, 'Descritivo'),
                          ),
                        ],
                      ),
                      PaymentMethod.revolut => _Steps(
                        lines: ['Abre o link e envia ${Fmt.money(widget.amount)}.'],
                        actions: [
                          OutlinedButton.icon(
                            onPressed: () => _open(Uri.https('revolut.me', '/${p.revolutTag}')),
                            icon: const Icon(LucideIcons.externalLink, size: 16),
                            label: Text('revolut.me/${p.revolutTag}'),
                          ),
                        ],
                      ),
                      PaymentMethod.paypal => _Steps(
                        lines: const ['O link já leva o valor preenchido.'],
                        actions: [
                          OutlinedButton.icon(
                            onPressed: () => _open(
                              Uri.https('paypal.me', '/${p.paypalUser}/${widget.amount.toStringAsFixed(2)}EUR'),
                            ),
                            icon: const Icon(LucideIcons.externalLink, size: 16),
                            label: Text('paypal.me/${p.paypalUser}'),
                          ),
                        ],
                      ),
                      PaymentMethod.cash => _Steps(
                        lines: ['Combina com ${widget.payeeName} entregar em mão.'],
                        actions: const [],
                      ),
                    },
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton.icon(
                onPressed: _selected == null ? null : () => Navigator.pop(context, _selected),
                icon: const Icon(LucideIcons.check, size: 18),
                label: Text(_selected == null ? 'Escolhe como pagaste' : 'Já paguei por ${_selected!.label}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.method, required this.selected, required this.onTap, required this.child});

  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: context.palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          side: BorderSide(
            color: selected ? context.colors.primary : context.palette.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      paymentIcon(method),
                      size: 20,
                      color: selected ? context.colors.primary : context.palette.mutedForeground,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(method.label, style: context.text.titleSmall)),
                    Icon(
                      selected ? LucideIcons.circleCheck : LucideIcons.circle,
                      size: 20,
                      color: selected ? context.colors.primary : context.palette.border,
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.topCenter,
                  child: selected
                      ? Padding(padding: const EdgeInsets.only(top: 12), child: child)
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.lines, required this.actions});

  final List<String> lines;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final l in lines)
        Text(l, style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground, fontSize: 13)),
      if (actions.isNotEmpty) const SizedBox(height: 10),
      for (final a in actions) Padding(padding: const EdgeInsets.only(bottom: 6), child: a),
    ],
  );
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value, required this.onCopy});

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(color: context.palette.muted, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.text.labelSmall?.copyWith(color: context.palette.mutedForeground)),
                SelectableText(value, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(tooltip: 'Copiar', onPressed: onCopy, icon: const Icon(LucideIcons.copy, size: 18)),
        ],
      ),
    );
  }
}
