import '../models/payments_models.dart';

/// Pagamentos dentro da app (Stripe). Só com servidor.
abstract class PaymentsRepository {
  Future<PayoutStatus> payoutStatus();

  /// Link da Stripe para ligar (ou continuar a ligar) a conta de quem recebe.
  Future<String> startOnboarding();

  /// Depois de voltar da Stripe.
  Future<PayoutStatus> refreshPayouts();

  /// Pagar a minha parte. Cartão/PayPal devolvem [InAppPayment.checkoutUrl];
  /// MB WAY envia o pedido para [phone] (sem ele, o número guardado).
  Future<InAppPayment> checkout(
    String memberId, {
    required String method,
    String? phone,
    bool savePhone = false,
    String? locale,
  });

  Future<InAppPayment> status(String paymentId);
}
