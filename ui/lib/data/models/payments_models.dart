import 'package:flutter/foundation.dart';

/// Pagamento dentro da app (ver backend/src/modules/payments).
@immutable
class InAppPayment {
  const InAppPayment({
    required this.id,
    required this.method,
    required this.amount,
    required this.fee,
    required this.total,
    required this.status,
    this.error,
    this.checkoutUrl,
  });

  final String id;

  /// `card`, `paypal` ou `mb_way`.
  final String method;
  final double amount;
  final double fee;
  final double total;

  /// `pending`, `processing` (transferência a caminho), `succeeded`, `failed` ou `canceled`.
  final String status;

  /// Código de erro da Stripe (ex.: `payment_method_customer_decline`).
  final String? error;

  /// Cartão / PayPal: a página de pagamento a abrir.
  final String? checkoutUrl;

  bool get isPending => status == 'pending';
  bool get succeeded => status == 'succeeded';

  /// Transferência autorizada: a parte já conta como paga, falta o dinheiro chegar.
  bool get isProcessing => status == 'processing';

  factory InAppPayment.fromJson(Map<String, dynamic> j) => InAppPayment(
    id: j['id'] as String,
    method: j['method'] as String,
    amount: (j['amount'] as num).toDouble(),
    fee: (j['fee'] as num).toDouble(),
    total: (j['total'] as num).toDouble(),
    status: j['status'] as String,
    error: j['error'] as String?,
    checkoutUrl: j['checkout_url'] as String?,
  );
}

/// Receber pagamentos na app (conta Stripe de quem compra).
@immutable
class PayoutStatus {
  const PayoutStatus({this.enabled = false, this.connected = false, this.ready = false});

  /// A Birthdayly tem pagamentos na app ligados.
  final bool enabled;
  final bool connected;
  final bool ready;

  static const off = PayoutStatus();

  factory PayoutStatus.fromJson(Map<String, dynamic> j) => PayoutStatus(
    enabled: j['enabled'] as bool? ?? false,
    connected: j['connected'] as bool? ?? false,
    ready: j['ready'] as bool? ?? false,
  );
}
