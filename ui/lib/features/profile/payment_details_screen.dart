import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants.dart';
import '../../core/i18n/translations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../data/models/payment.dart';
import '../groups/payment_widgets.dart';

/// Como preferes receber quando és tu a comprar a prenda (MB WAY, IBAN,
/// Revolut, PayPal, Skrill, em mão). O dinheiro não passa pela app: quem paga
/// vê estes dados prontos a copiar e envia-te diretamente.
class PaymentDetailsScreen extends ConsumerStatefulWidget {
  const PaymentDetailsScreen({super.key});

  @override
  ConsumerState<PaymentDetailsScreen> createState() => _PaymentDetailsScreenState();
}

class _PaymentDetailsScreenState extends ConsumerState<PaymentDetailsScreen> {
  final _form = GlobalKey<FormState>();
  late PaymentDetails _details = _initial();
  bool _saving = false;

  /// Sem MB WAY indicado, sugere o telemóvel da conta (português).
  PaymentDetails _initial() {
    final user = ref.read(currentUserProvider);
    final d = user?.payment ?? PaymentDetails.empty;
    if (d.mbwayPhone.isEmpty && (user?.phone.startsWith('+351') ?? false)) {
      final suggested = PaymentFormat.normalizePhone(user!.phone);
      if (suggested != null) return d.copyWith(mbwayPhone: suggested);
    }
    return d;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _saving = true);
    final ok = await runGuarded(
      context,
      () => ref.read(authRepositoryProvider).updateProfile(user.copyWith(payment: _details)),
      success: context.tr(Keys.receiveSaved),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(Keys.paymentsScreenTitle)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
              child: Text(context.tr(Keys.commonSave)),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            AppCard(
              color: context.palette.accent,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.shieldCheck, color: context.palette.accentForeground, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr(Keys.receiveScreenHint),
                      style: TextStyle(color: context.palette.accentForeground),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            PaymentDetailsFields(initial: _details, onChanged: (d) => _details = d),
          ],
        ),
      ),
    );
  }
}
