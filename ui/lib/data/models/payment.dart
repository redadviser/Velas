import 'package:flutter/foundation.dart';

import '../../core/i18n/translations.dart';

/// Formas de pagamento para acertar contas entre amigos. A app não movimenta
/// dinheiro: abre o link/app certo e regista o "já paguei".
///
/// [card] (VISA / Mastercard) paga-se na página segura do Revolut ou do PayPal
/// de quem recebe, que aceitam cartão de quem não tem conta.
enum PaymentMethod {
  card,
  mbway,
  paypal,
  skrill,
  revolut,
  cash;

  /// Nome na língua da app (chaves `pay.method.<nome>`).
  String get label => tr('pay.method.$name');

  static PaymentMethod? tryParse(String? v) => PaymentMethod.values.where((m) => m.name == v).firstOrNull;
}

/// Dados que permitem a outros membros de um grupo pagar-te.
@immutable
class PaymentDetails {
  const PaymentDetails({
    this.mbwayPhone = '',
    this.revolutTag = '',
    this.paypalUser = '',
    this.skrillEmail = '',
    this.acceptsCash = true,
  });

  final String mbwayPhone;
  final String revolutTag;
  final String paypalUser;
  final String skrillEmail;
  final bool acceptsCash;

  static const empty = PaymentDetails();

  bool get hasAnyDigital =>
      mbwayPhone.isNotEmpty || revolutTag.isNotEmpty || paypalUser.isNotEmpty || skrillEmail.isNotEmpty;

  /// Cartão VISA / Mastercard: pelo Revolut (não pede conta) ou pelo PayPal.
  bool get acceptsCard => revolutTag.isNotEmpty || paypalUser.isNotEmpty;

  bool accepts(PaymentMethod m) => switch (m) {
    PaymentMethod.card => acceptsCard,
    PaymentMethod.mbway => mbwayPhone.isNotEmpty,
    PaymentMethod.paypal => paypalUser.isNotEmpty,
    PaymentMethod.skrill => skrillEmail.isNotEmpty,
    PaymentMethod.revolut => revolutTag.isNotEmpty,
    PaymentMethod.cash => acceptsCash,
  };

  /// Os métodos que quem recebe aceita, pela ordem de [PaymentMethod].
  List<PaymentMethod> get methods => PaymentMethod.values.where(accepts).toList();

  PaymentDetails copyWith({
    String? mbwayPhone,
    String? revolutTag,
    String? paypalUser,
    String? skrillEmail,
    bool? acceptsCash,
  }) => PaymentDetails(
    mbwayPhone: mbwayPhone ?? this.mbwayPhone,
    revolutTag: revolutTag ?? this.revolutTag,
    paypalUser: paypalUser ?? this.paypalUser,
    skrillEmail: skrillEmail ?? this.skrillEmail,
    acceptsCash: acceptsCash ?? this.acceptsCash,
  );

  Map<String, dynamic> toJson() => {
    'mbway_phone': mbwayPhone,
    'revolut_tag': revolutTag,
    'paypal_user': paypalUser,
    'skrill_email': skrillEmail,
    'accepts_cash': acceptsCash,
  };

  factory PaymentDetails.fromJson(Map<String, dynamic>? j) {
    if (j == null) return empty;
    return PaymentDetails(
      mbwayPhone: j['mbway_phone'] as String? ?? '',
      revolutTag: j['revolut_tag'] as String? ?? '',
      paypalUser: j['paypal_user'] as String? ?? '',
      skrillEmail: j['skrill_email'] as String? ?? '',
      acceptsCash: j['accepts_cash'] as bool? ?? true,
    );
  }
}

/// Validação e formatação dos dados de pagamento.
class PaymentFormat {
  const PaymentFormat._();

  /// Telemóvel português (9 dígitos a começar por 9), com ou sem +351.
  static String? normalizePhone(String input) {
    var d = input.replaceAll(RegExp(r'[\s\-()]'), '');
    if (d.startsWith('+351')) d = d.substring(4);
    if (d.startsWith('00351')) d = d.substring(5);
    return RegExp(r'^9[1236]\d{7}$').hasMatch(d) ? d : null;
  }

  static String displayPhone(String d) =>
      d.length == 9 ? '${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}' : d;

  static String cleanHandle(String input) => input.trim().replaceFirst(RegExp(r'^@'), '').replaceAll(' ', '');

  /// Email (Skrill), em minúsculas; `null` se não parecer um email.
  static String? normalizeEmail(String input) {
    final s = input.trim().toLowerCase();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s) ? s : null;
  }
}
