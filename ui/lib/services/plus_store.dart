import 'dart:io';

import 'package:adapty_flutter/adapty_flutter.dart';
import 'package:flutter/foundation.dart';

import '../core/utils/errors.dart';

/// Um plano do Birthdayly+ à venda na loja (App Store / Google Play), com o
/// preço já na moeda e no formato do telemóvel.
typedef StorePlan = ({String id, bool yearly, String price, double amount, Object product});

/// Comprar o Birthdayly+ na loja. A app só compra e restaura: quem diz se a
/// conta tem o plano é o servidor, depois de confirmar com o Adapty.
abstract class PlusStore {
  /// Os planos à venda (mensal e anual).
  Future<List<StorePlan>> plans();

  /// `true` se ficou comprado; `false` se a pessoa desistiu.
  Future<bool> buy(StorePlan plan);

  /// Compras feitas antes (outro telemóvel, reinstalação).
  Future<void> restore();
}

/// Adapty (`--dart-define` ADAPTY_PUBLIC_KEY e, se for outro, ADAPTY_PLACEMENT_ID).
class AdaptyStore implements PlusStore {
  AdaptyStore._();
  static final instance = AdaptyStore._();

  static const _publicKey = String.fromEnvironment('ADAPTY_PUBLIC_KEY');
  static const _placement = String.fromEnvironment('ADAPTY_PLACEMENT_ID', defaultValue: 'plans');

  /// Configurado e num telemóvel (iOS ou Android).
  static bool get available => _publicKey.isNotEmpty && !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool _activated = false;
  String? _userId;

  /// A conta da Birthdayly é o "customer user id" no Adapty (é por ele que o servidor pergunta).
  Future<void> identify(String userId) async {
    if (!available || _userId == userId) return;
    try {
      if (!_activated) {
        await Adapty().activate(configuration: AdaptyConfiguration(apiKey: _publicKey)..withCustomerUserId(userId));
        _activated = true;
      } else {
        await Adapty().identify(userId);
      }
      _userId = userId;
    } catch (_) {
      // Sem loja (ex.: emulador sem Google Play): fica sem compras.
    }
  }

  Future<void> logout() async {
    if (!_activated || _userId == null) return;
    _userId = null;
    await Adapty().logout().catchError((_) {});
  }

  @override
  Future<List<StorePlan>> plans() async {
    final flow = await Adapty().getFlow(placementId: _placement);
    final products = await Adapty().getPaywallProducts(flow: flow);
    return [
      for (final p in products)
        if (p.subscription?.period.unit case final unit? when unit == AdaptyPeriodUnit.month || unit == AdaptyPeriodUnit.year)
          (
            id: p.vendorProductId,
            yearly: unit == AdaptyPeriodUnit.year,
            price: p.price.localizedString ?? '${p.price.amount}',
            amount: p.price.amount,
            product: p,
          ),
    ];
  }

  @override
  Future<bool> buy(StorePlan plan) async {
    try {
      final result = await Adapty().makePurchase(product: plan.product as AdaptyPaywallProduct);
      return switch (result) {
        AdaptyPurchaseResultSuccess() => true,
        AdaptyPurchaseResultUserCancelled() => false,
        AdaptyPurchaseResultPending() => throw const AppException(
          'A compra está pendente na loja. Quando for aprovada, o Birthdayly+ fica ativo.',
        ),
      };
    } on AdaptyError catch (e) {
      if (e.code == AdaptyErrorCode.paymentCancelled) return false;
      throw AppException('Não foi possível concluir a compra: ${e.message}');
    }
  }

  @override
  Future<void> restore() async {
    await Adapty().restorePurchases();
  }
}
