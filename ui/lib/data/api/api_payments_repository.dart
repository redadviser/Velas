import '../../core/constants.dart';
import '../../core/i18n/translations.dart';
import '../../core/utils/errors.dart';
import '../models/payments_models.dart';
import '../repositories/payments_repository.dart';
import 'api_client.dart';

class ApiPaymentsRepository implements PaymentsRepository {
  ApiPaymentsRepository(this._api);

  final ApiClient _api;

  static Map<String, dynamic> _map(Object? v) => (v as Map).cast<String, dynamic>();

  @override
  Future<PayoutStatus> payoutStatus() async => PayoutStatus.fromJson(_map(await _api.get('/me/payouts')));

  @override
  Future<String> startOnboarding() async => _map(await _api.post('/me/payouts/onboarding'))['url'] as String;

  @override
  Future<PayoutStatus> refreshPayouts() async => PayoutStatus.fromJson(_map(await _api.post('/me/payouts/refresh')));

  @override
  Future<InAppPayment> checkout(
    String memberId, {
    required String method,
    String? phone,
    bool savePhone = false,
    String? locale,
  }) async {
    try {
      return InAppPayment.fromJson(
        _map(
          await _api.post('/group-members/$memberId/checkout', {
            'method': method,
            'phone': ?phone,
            'save_phone': savePhone,
            'locale': ?locale,
          }),
        ),
      );
    } on ApiException catch (e) {
      throw switch (e.code) {
        'invalid_phone' => AppException(tr(Keys.payInAppPhoneInvalid)),
        'payment_failed' || 'payments_unavailable' => AppException(tr(Keys.payInAppErrorGeneric)),
        _ => e,
      };
    }
  }

  @override
  Future<InAppPayment> status(String paymentId) async => InAppPayment.fromJson(_map(await _api.get('/payments/$paymentId')));
}
