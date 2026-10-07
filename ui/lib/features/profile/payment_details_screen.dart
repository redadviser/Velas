import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../data/models/payment.dart';
import '../groups/payment_widgets.dart';

/// Os dados que os amigos usam para te pagar quando és tu a comprar a prenda.
class PaymentDetailsScreen extends ConsumerStatefulWidget {
  const PaymentDetailsScreen({super.key});

  @override
  ConsumerState<PaymentDetailsScreen> createState() => _PaymentDetailsScreenState();
}

class _PaymentDetailsScreenState extends ConsumerState<PaymentDetailsScreen> {
  final _form = GlobalKey<FormState>();
  late PaymentDetails _details = ref.read(currentUserProvider)?.payment ?? PaymentDetails.empty;
  bool _saving = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _saving = true);
    final ok = await runGuarded(
      context,
      () => ref.read(authRepositoryProvider).updateProfile(user.copyWith(payment: _details)),
      success: 'Dados de pagamento guardados.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dados de pagamento'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
              child: const Text('Guardar'),
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
                      'Estes dados só são mostrados às pessoas de um grupo em que és tu a comprar a prenda, '
                      'para te poderem enviar a parte delas. A Velas não movimenta dinheiro.',
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
