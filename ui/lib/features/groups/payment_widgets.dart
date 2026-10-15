import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/birthday_utils.dart';
import '../../core/widgets/common.dart';
import '../../data/models/payment.dart';
import '../auth/auth_widgets.dart';

IconData paymentIcon(PaymentMethod m) => switch (m) {
  PaymentMethod.card => LucideIcons.creditCard,
  PaymentMethod.mbway => LucideIcons.smartphone,
  PaymentMethod.paypal => LucideIcons.wallet,
  PaymentMethod.skrill => LucideIcons.wallet,
  PaymentMethod.revolut => LucideIcons.creditCard,
  PaymentMethod.transfer => LucideIcons.landmark,
  PaymentMethod.cash => LucideIcons.banknote,
};

/// Logótipo do método (ver assets/images/CREDITS.md), ou `null` se não tiver.
String? paymentLogoAsset(PaymentMethod m) => switch (m) {
  PaymentMethod.card => 'assets/images/payments/card.png',
  PaymentMethod.mbway => 'assets/images/payments/mbway.png',
  PaymentMethod.paypal => 'assets/images/payments/paypal.png',
  PaymentMethod.skrill => 'assets/images/payments/skrill.png',
  PaymentMethod.revolut => 'assets/images/payments/revolut.png',
  PaymentMethod.transfer || PaymentMethod.cash => null,
};

/// Logótipo (cartão VISA/Mastercard, MB WAY, PayPal, Skrill, Revolut); ícone para transferência e dinheiro.
class PaymentLogo extends StatelessWidget {
  const PaymentLogo(this.method, {super.key, this.size = 24, this.color});

  final PaymentMethod method;
  final double size;

  /// Cor do ícone (métodos sem logótipo).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final asset = paymentLogoAsset(method);
    if (asset == null) {
      return SizedBox.square(
        dimension: size,
        child: Icon(paymentIcon(method), size: size * 0.82, color: color ?? context.palette.mutedForeground),
      );
    }
    return Image.asset(
      asset,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      semanticLabel: method.label,
    );
  }
}

/// Logótipo dentro de um campo de texto.
Widget _fieldLogo(PaymentMethod m) => Padding(padding: const EdgeInsets.all(12), child: PaymentLogo(m, size: 22));

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
  late final _skrill = TextEditingController(text: widget.initial.skrillEmail);
  late bool _cash = widget.initial.acceptsCash;

  @override
  void dispose() {
    for (final c in [_phone, _iban, _holder, _revolut, _paypal, _skrill]) {
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
      skrillEmail: PaymentFormat.normalizeEmail(_skrill.text) ?? '',
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
          decoration: InputDecoration(hintText: '912 345 678', prefixIcon: _fieldLogo(PaymentMethod.mbway)),
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
                    decoration: InputDecoration(hintText: '@utilizador', prefixIcon: _fieldLogo(PaymentMethod.revolut)),
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
                    decoration: InputDecoration(hintText: 'utilizador', prefixIcon: _fieldLogo(PaymentMethod.paypal)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const PaymentLogo(PaymentMethod.card, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr(Keys.payFormCardHint),
                style: context.text.bodySmall?.copyWith(color: context.palette.mutedForeground),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        FieldLabel(context.tr(Keys.payFormSkrill)),
        TextFormField(
          controller: _skrill,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          onChanged: (_) => _emit(),
          validator: (v) => (v == null || v.trim().isEmpty || PaymentFormat.normalizeEmail(v) != null)
              ? null
              : context.tr(Keys.payFormSkrillInvalid),
          decoration: InputDecoration(hintText: 'nome@email.com', prefixIcon: _fieldLogo(PaymentMethod.skrill)),
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

/// Ecrã "Pagar a …": escolher o método (cartão VISA/Mastercard, MB WAY,
/// PayPal, Skrill, Revolut, transferência ou em mão), enviar pelo link ou app
/// certos e marcar "Já paguei". Devolve o método, ou `null` se cancelado.
///
/// A app não movimenta dinheiro: o cartão paga-se na página segura do Revolut
/// ou do PayPal de quem recebe.
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

  PaymentDetails get _p => widget.payee;
  String get _amountPlain => widget.amount.toStringAsFixed(2).replaceAll('.', ',');
  String get _money => Fmt.money(widget.amount);

  Future<void> _copy(String value, String what) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) showMessage(context, context.tr(Keys.payCopied, {'what': what}));
  }

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) showMessage(context, context.tr(Keys.payOpenFailed));
  }

  Uri get _revolutLink => Uri.https('revolut.me', '/${_p.revolutTag}');
  Uri get _paypalLink => Uri.https('paypal.me', '/${_p.paypalUser}/${widget.amount.toStringAsFixed(2)}EUR');

  /// O que fazer para "enviar" com cada método.
  ({List<String> steps, List<Widget> details, String? sendLabel, Future<void> Function()? send}) _flow(
    PaymentMethod m,
  ) {
    final name = widget.payeeName;
    return switch (m) {
      PaymentMethod.card => (
        steps: [
          context.tr(_p.revolutTag.isNotEmpty ? Keys.payStepsCardRevolut : Keys.payStepsCardPaypal, {'name': name}),
        ],
        details: const [],
        sendLabel: context.tr(Keys.paySendCard, {'amount': _money}),
        send: () => _open(_p.revolutTag.isNotEmpty ? _revolutLink : _paypalLink),
      ),
      PaymentMethod.mbway => (
        steps: [context.tr(Keys.payStepsMbway)],
        details: [
          _CopyRow(
            label: context.tr(Keys.payFieldNumber),
            value: PaymentFormat.displayPhone(_p.mbwayPhone),
            onCopy: () => _copy(_p.mbwayPhone, context.tr(Keys.payFieldNumber)),
          ),
        ],
        sendLabel: context.tr(Keys.paySendCopyNumber),
        send: () => _copy(_p.mbwayPhone, context.tr(Keys.payFieldNumber)),
      ),
      PaymentMethod.paypal => (
        steps: [context.tr(Keys.payStepsPaypal)],
        details: const [],
        sendLabel: context.tr(Keys.paySendLink, {'amount': _money, 'method': m.label}),
        send: () => _open(_paypalLink),
      ),
      PaymentMethod.skrill => (
        steps: [
          context.tr(Keys.payStepsSkrill, {'amount': _money}),
        ],
        details: [
          _CopyRow(
            label: context.tr(Keys.payFieldEmail),
            value: _p.skrillEmail,
            onCopy: () => _copy(_p.skrillEmail, context.tr(Keys.payFieldEmail)),
          ),
        ],
        sendLabel: context.tr(Keys.paySendSkrill),
        send: () async {
          await _copy(_p.skrillEmail, context.tr(Keys.payFieldEmail));
          await _open(Uri.https('www.skrill.com', '/'));
        },
      ),
      PaymentMethod.revolut => (
        steps: [
          context.tr(Keys.payStepsRevolut, {'amount': _money}),
        ],
        details: const [],
        sendLabel: context.tr(Keys.paySendLink, {'amount': _money, 'method': m.label}),
        send: () => _open(_revolutLink),
      ),
      PaymentMethod.transfer => (
        steps: [context.tr(Keys.payStepsTransfer)],
        details: [
          _CopyRow(
            label: context.tr(Keys.payFieldIban),
            value: PaymentFormat.displayIban(_p.iban),
            onCopy: () => _copy(_p.iban, context.tr(Keys.payFieldIban)),
          ),
          if (_p.ibanHolder.isNotEmpty)
            _CopyRow(
              label: context.tr(Keys.payFieldHolder),
              value: _p.ibanHolder,
              onCopy: () => _copy(_p.ibanHolder, context.tr(Keys.payFieldHolder)),
            ),
          _CopyRow(
            label: context.tr(Keys.payFieldReference),
            value: widget.reference,
            onCopy: () => _copy(widget.reference, context.tr(Keys.payFieldReference)),
          ),
        ],
        sendLabel: context.tr(Keys.paySendIban),
        send: () => _copy(_p.iban, context.tr(Keys.payFieldIban)),
      ),
      PaymentMethod.cash => (
        steps: [
          context.tr(Keys.payStepsCash, {'name': name}),
        ],
        details: const [],
        sendLabel: null,
        send: null,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final selected = _selected;
    final flow = selected == null ? null : _flow(selected);
    final muted = context.palette.mutedForeground;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              children: [
                Text(
                  context.tr(Keys.payTitle, {'name': widget.payeeName}),
                  style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_money, style: AppTheme.display(context, size: 40)),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: context.tr(Keys.payCopyAmount),
                      onPressed: () => _copy(_amountPlain, context.tr(Keys.payCopyAmount)),
                      icon: Icon(LucideIcons.copy, size: 18, color: muted),
                    ),
                  ],
                ),
                Text(widget.reference, style: TextStyle(color: muted)),
                if (!p.hasAnyDigital) ...[
                  const SizedBox(height: 16),
                  AppCard(
                    color: context.palette.muted,
                    child: Text(
                      context.tr(Keys.payNoMethods, {'name': widget.payeeName}),
                      style: TextStyle(color: muted),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(context.tr(Keys.payChoose), style: context.text.titleSmall),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.95,
                  children: [
                    for (final m in PaymentMethod.values)
                      _MethodChoice(
                        method: m,
                        available: p.accepts(m),
                        selected: selected == m,
                        onTap: () => p.accepts(m)
                            ? setState(() => _selected = m)
                            : showMessage(context, context.tr(Keys.payUnavailableHint, {'name': widget.payeeName})),
                      ),
                  ],
                ),
                if (selected != null && flow != null) ...[
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            PaymentLogo(selected, size: 28),
                            const SizedBox(width: 10),
                            Expanded(child: Text(selected.label, style: context.text.titleSmall)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        for (final line in flow.steps)
                          Text(line, style: context.text.bodySmall?.copyWith(color: muted, fontSize: 13)),
                        if (flow.details.isNotEmpty) const SizedBox(height: 10),
                        for (final d in flow.details) Padding(padding: const EdgeInsets.only(bottom: 6), child: d),
                        if (flow.send != null) ...[
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: flow.send,
                            icon: Icon(
                              selected == PaymentMethod.mbway || selected == PaymentMethod.transfer
                                  ? LucideIcons.copy
                                  : LucideIcons.send,
                              size: 18,
                            ),
                            label: Text(flow.sendLabel!),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.tr(Keys.payAfterSend, {'name': widget.payeeName}),
                            textAlign: TextAlign.center,
                            style: context.text.bodySmall?.copyWith(color: muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton.icon(
                onPressed: selected == null ? null : () => Navigator.pop(context, selected),
                icon: const Icon(LucideIcons.check, size: 18),
                label: Text(
                  selected == null
                      ? context.tr(Keys.payConfirmChoose)
                      : context.tr(Keys.payConfirm, {'method': selected.label}),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Um método na grelha: logótipo e nome (indisponível se quem recebe não o indicou).
class _MethodChoice extends StatelessWidget {
  const _MethodChoice({required this.method, required this.available, required this.selected, required this.onTap});

  final PaymentMethod method;
  final bool available;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.mutedForeground;
    return Semantics(
      button: true,
      selected: selected,
      enabled: available,
      child: Opacity(
        opacity: available ? 1 : 0.45,
        child: Material(
          color: selected ? context.palette.accent : context.palette.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? context.colors.primary : context.palette.border,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PaymentLogo(method, size: 40, color: selected ? context.colors.primary : muted),
                  const SizedBox(height: 8),
                  Text(
                    method.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    !available
                        ? context.tr(Keys.payUnavailable)
                        : method == PaymentMethod.card
                        ? context.tr(Keys.payCardBrands)
                        : ' ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(color: muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
          IconButton(
            tooltip: context.tr(Keys.payCopy),
            onPressed: onCopy,
            icon: const Icon(LucideIcons.copy, size: 18),
          ),
        ],
      ),
    );
  }
}
