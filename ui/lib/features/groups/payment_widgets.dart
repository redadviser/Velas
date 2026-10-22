import 'dart:async';

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
import '../../core/utils/errors.dart';
import '../../data/models/payment.dart';
import '../../data/models/payments_models.dart';
import '../auth/auth_widgets.dart';

IconData paymentIcon(PaymentMethod m) => switch (m) {
  PaymentMethod.card => LucideIcons.creditCard,
  PaymentMethod.mbway => LucideIcons.smartphone,
  PaymentMethod.paypal => LucideIcons.wallet,
  PaymentMethod.skrill => LucideIcons.wallet,
  PaymentMethod.revolut => LucideIcons.creditCard,
  PaymentMethod.cash => LucideIcons.banknote,
};

/// Logótipo do método (ver assets/images/CREDITS.md), ou `null` se não tiver.
String? paymentLogoAsset(PaymentMethod m) => switch (m) {
  PaymentMethod.card => 'assets/images/payments/card.png',
  PaymentMethod.mbway => 'assets/images/payments/mbway.png',
  PaymentMethod.paypal => 'assets/images/payments/paypal.png',
  PaymentMethod.skrill => 'assets/images/payments/skrill.png',
  PaymentMethod.revolut => 'assets/images/payments/revolut.png',
  PaymentMethod.cash => null,
};

/// Logótipo (cartão VISA/Mastercard, MB WAY, PayPal, Skrill, Revolut); ícone para o dinheiro.
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
  late final _revolut = TextEditingController(text: widget.initial.revolutTag);
  late final _paypal = TextEditingController(text: widget.initial.paypalUser);
  late final _skrill = TextEditingController(text: widget.initial.skrillEmail);
  late bool _cash = widget.initial.acceptsCash;

  @override
  void dispose() {
    for (final c in [_phone, _revolut, _paypal, _skrill]) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged(
    PaymentDetails(
      mbwayPhone: PaymentFormat.normalizePhone(_phone.text) ?? '',
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

/// Resultado da janela "Pagar a …".
class PayResult {
  const PayResult(this.method, {this.paidInApp = false, this.processing = false});

  final PaymentMethod method;

  /// Pago dentro da app (Stripe): a parte já ficou paga (e confirmada) no servidor.
  final bool paidInApp;

  /// Pagamento autorizado mas com o dinheiro a caminho: fica confirmado quando chegar.
  final bool processing;
}

/// Pagar dentro da app (Stripe). Dado por quem abre a janela, que sabe o
/// membro e o repositório; sem ele só há os links e "Já paguei".
class InAppPay {
  const InAppPay({required this.start, required this.poll, this.savedPhone = ''});

  final Future<InAppPayment> Function(PaymentMethod method, {String? phone, bool savePhone}) start;
  final Future<InAppPayment> Function(String paymentId) poll;

  /// Número MB WAY associado à conta (E.164), ou vazio.
  final String savedPhone;
}

/// Ecrã "Pagar a …": escolher o método (cartão VISA/Mastercard, MB WAY,
/// PayPal, Skrill, Revolut ou em mão) e pagar.
///
/// Se quem compra ligou a conta Stripe ([PaymentDetails.inApp]) e há [inApp],
/// cartão e PayPal pagam-se na página segura da Stripe e o MB WAY envia um
/// pedido para o telemóvel; a parte fica paga sozinha. Os outros métodos (ou
/// sem Stripe) abrem o link/app certos e terminam com "Já paguei".
Future<PayResult?> showPaySheet(
  BuildContext context, {
  required String payeeName,
  required double amount,
  required PaymentDetails payee,
  required String reference,
  InAppPay? inApp,
}) {
  return showModalBottomSheet<PayResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PaySheet(payeeName: payeeName, amount: amount, payee: payee, reference: reference, inApp: inApp),
  );
}

class _PaySheet extends StatefulWidget {
  const _PaySheet({
    required this.payeeName,
    required this.amount,
    required this.payee,
    required this.reference,
    this.inApp,
  });

  final String payeeName;
  final double amount;
  final PaymentDetails payee;
  final String reference;
  final InAppPay? inApp;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> with WidgetsBindingObserver {
  late PaymentMethod? _selected = widget.payee.methods.firstOrNull;

  // Pagamento dentro da app.
  late final _phone = TextEditingController(
    text: widget.inApp?.savedPhone.isNotEmpty ?? false ? PaymentFormat.displayE164(widget.inApp!.savedPhone) : '',
  );
  late bool _editingPhone = widget.inApp?.savedPhone.isEmpty ?? true;
  bool _savePhone = true;
  bool _starting = false;
  InAppPayment? _payment;
  String? _error;
  Timer? _poll;

  PaymentDetails get _p => widget.payee;
  String get _amountPlain => widget.amount.toStringAsFixed(2).replaceAll('.', ',');
  String get _money => Fmt.money(widget.amount);
  bool get _waiting => _payment?.isPending ?? false;

  bool _inAppFor(PaymentMethod m) => widget.inApp != null && _p.payInApp(m);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _phone.dispose();
    super.dispose();
  }

  // Ao voltar da página de pagamento (ou da app MB WAY), vê logo como ficou.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waiting) _check();
  }

  Future<void> _copy(String value, String what) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) showMessage(context, context.tr(Keys.payCopied, {'what': what}));
  }

  Future<void> _open(Uri uri, {bool inApp = false}) async {
    var ok = false;
    if (inApp) ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView).catchError((_) => false);
    if (!ok) ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) showMessage(context, context.tr(Keys.payOpenFailed));
  }

  String _errorText(InAppPayment p) {
    final code = p.error ?? '';
    if (p.status == 'canceled') return context.tr(Keys.payInAppErrorCanceled);
    if (code.contains('decline')) return context.tr(Keys.payInAppErrorDeclined);
    if (code.contains('expired')) return context.tr(Keys.payInAppErrorExpired);
    if (code.contains('not_available')) return context.tr(Keys.payInAppErrorNotAvailable);
    return context.tr(Keys.payInAppErrorGeneric);
  }

  void _apply(InAppPayment p) {
    if (!mounted) return;
    if (p.succeeded || p.isProcessing) {
      _poll?.cancel();
      Navigator.pop(context, PayResult(_selected!, paidInApp: true, processing: p.isProcessing));
      return;
    }
    setState(() {
      _payment = p;
      if (!p.isPending) {
        _poll?.cancel();
        _error = _errorText(p);
      }
    });
  }

  Future<void> _check() async {
    final p = _payment;
    if (p == null || widget.inApp == null) return;
    try {
      _apply(await widget.inApp!.poll(p.id));
    } catch (_) {
      // Falhou a ligação: tenta outra vez no próximo ciclo.
    }
  }

  Future<void> _startInApp(PaymentMethod m) async {
    String? phone;
    if (m == PaymentMethod.mbway && _editingPhone) {
      phone = PaymentFormat.toE164(_phone.text);
      if (phone == null) {
        setState(() => _error = context.tr(Keys.payInAppPhoneInvalid));
        return;
      }
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final p = await widget.inApp!.start(m, phone: phone, savePhone: _editingPhone && _savePhone);
      if (!mounted) return;
      _apply(p);
      if (p.isPending) {
        _poll?.cancel();
        _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
        if (p.checkoutUrl != null) await _open(Uri.parse(p.checkoutUrl!), inApp: true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _stopWaiting() {
    _poll?.cancel();
    setState(() => _payment = null);
  }

  Uri get _revolutLink => Uri.https('revolut.me', '/${_p.revolutTag}');
  Uri get _paypalLink => Uri.https('paypal.me', '/${_p.paypalUser}/${widget.amount.toStringAsFixed(2)}EUR');

  /// Sem pagamento na app: o que fazer para "enviar" com cada método.
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

  /// Pagar dentro da app: comissão, número MB WAY e o botão; depois, a espera.
  Widget _inAppPanel(PaymentMethod m) {
    final muted = context.palette.mutedForeground;
    final (:fee, :total) = _p.withFee(m, widget.amount);
    final totalText = Fmt.money(total);

    if (_waiting) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Center(child: SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.5))),
          const SizedBox(height: 14),
          Text(
            m == PaymentMethod.mbway
                ? context.tr(Keys.payInAppWaitingMbway, {'total': totalText})
                : context.tr(Keys.payInAppWaitingCheckout),
            textAlign: TextAlign.center,
            style: context.text.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(Keys.payInAppWaitingHint),
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(color: muted),
          ),
          if (_payment?.checkoutUrl != null)
            TextButton(
              onPressed: () => _open(Uri.parse(_payment!.checkoutUrl!), inApp: true),
              child: Text(context.tr(Keys.payInAppReopen)),
            ),
          TextButton(onPressed: _stopWaiting, child: Text(context.tr(Keys.payInAppStopWaiting))),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(
            switch (m) {
              PaymentMethod.mbway => Keys.payInAppMbwaySteps,
              PaymentMethod.paypal => Keys.payInAppPaypalSteps,
              PaymentMethod.revolut => Keys.payInAppRevolutSteps,
              _ => Keys.payInAppCardSteps,
            },
            {'name': widget.payeeName},
          ),
          style: context.text.bodySmall?.copyWith(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: context.palette.muted, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(Keys.payInAppFeeLine, {'amount': _money, 'fee': Fmt.money(fee), 'total': totalText}),
                style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (_p.inAppServiceFee > 0)
                Text(
                  context.tr(Keys.payInAppServiceNote, {'fee': Fmt.money(_p.inAppServiceFee)}),
                  style: context.text.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
        ),
        if (m == PaymentMethod.mbway) ...[
          const SizedBox(height: 12),
          if (!_editingPhone)
            _CopyRow(
              label: context.tr(Keys.payInAppPhoneLabel),
              value: PaymentFormat.displayE164(widget.inApp!.savedPhone),
              onCopy: () => _copy(widget.inApp!.savedPhone, context.tr(Keys.payFieldNumber)),
            )
          else ...[
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
              decoration: InputDecoration(
                labelText: context.tr(Keys.payInAppPhoneLabel),
                hintText: '912 345 678',
                prefixIcon: _fieldLogo(PaymentMethod.mbway),
              ),
            ),
            CheckboxListTile(
              value: _savePhone,
              onChanged: (v) => setState(() => _savePhone = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(context.tr(Keys.payInAppSavePhone)),
            ),
          ],
          if (!_editingPhone)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  _editingPhone = true;
                  _phone.clear();
                  _savePhone = true;
                }),
                child: Text(context.tr(Keys.payInAppChangePhone)),
              ),
            ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _starting ? null : () => _startInApp(m),
          icon: _starting
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(switch (m) {
                  PaymentMethod.mbway => LucideIcons.smartphone,
                  _ => LucideIcons.lock,
                }, size: 18),
          label: Text(switch (m) {
            PaymentMethod.mbway => context.tr(Keys.payInAppSendRequest, {'total': totalText}),
            PaymentMethod.paypal => context.tr(Keys.payInAppPayPaypal, {'total': totalText}),
            PaymentMethod.revolut => context.tr(Keys.payInAppPayRevolut, {'total': totalText}),
            _ => context.tr(Keys.payInAppPayCard, {'total': totalText}),
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final selected = _selected;
    final inApp = selected != null && _inAppFor(selected);
    final flow = selected == null || inApp ? null : _flow(selected);
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
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
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
                if (!p.hasAnyDigital && !p.inApp) ...[
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
                IgnorePointer(
                  // Enquanto se espera pela confirmação, o método não muda.
                  ignoring: _waiting,
                  child: GridView.count(
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
                          inApp: _inAppFor(m),
                          selected: selected == m,
                          onTap: () => p.accepts(m)
                              ? setState(() {
                                  _selected = m;
                                  _error = null;
                                })
                              : showMessage(context, context.tr(Keys.payUnavailableHint, {'name': widget.payeeName})),
                        ),
                    ],
                  ),
                ),
                if (selected != null) ...[
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
                            if (inApp)
                              Pill(
                                icon: LucideIcons.shieldCheck,
                                label: context.tr(Keys.payInAppBadge),
                                background: context.palette.success.withValues(alpha: 0.14),
                                foreground: context.palette.success,
                                dense: true,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (inApp)
                          _inAppPanel(selected)
                        else if (flow != null) ...[
                          for (final line in flow.steps)
                            Text(line, style: context.text.bodySmall?.copyWith(color: muted, fontSize: 13)),
                          if (flow.details.isNotEmpty) const SizedBox(height: 10),
                          for (final d in flow.details) Padding(padding: const EdgeInsets.only(bottom: 6), child: d),
                          if (flow.send != null) ...[
                            const SizedBox(height: 8),
                            FilledButton.tonalIcon(
                              onPressed: flow.send,
                              icon: Icon(
                                selected == PaymentMethod.mbway ? LucideIcons.copy : LucideIcons.send,
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
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Dentro da app a confirmação é automática; "Já paguei" é só para os outros métodos.
          if (!inApp)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton.icon(
                  onPressed: selected == null ? null : () => Navigator.pop(context, PayResult(selected)),
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
  const _MethodChoice({
    required this.method,
    required this.available,
    required this.selected,
    required this.onTap,
    this.inApp = false,
  });

  final PaymentMethod method;
  final bool available;
  final bool selected;
  final VoidCallback onTap;

  /// Paga-se dentro da app (cadeado verde).
  final bool inApp;

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
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      PaymentLogo(method, size: 40, color: selected ? context.colors.primary : muted),
                      if (inApp)
                        Positioned(
                          right: -6,
                          bottom: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: context.palette.success,
                              shape: BoxShape.circle,
                              border: Border.all(color: context.palette.card, width: 1.5),
                            ),
                            child: const Icon(LucideIcons.lock, size: 9, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
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
