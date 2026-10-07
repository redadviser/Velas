import 'package:flutter/foundation.dart';

/// Formas de pagamento habituais em Portugal para acertar contas entre amigos.
enum PaymentMethod {
  mbway('MB WAY'),
  transfer('Transferência'),
  revolut('Revolut'),
  paypal('PayPal'),
  cash('Dinheiro');

  const PaymentMethod(this.label);
  final String label;

  static PaymentMethod? tryParse(String? v) => PaymentMethod.values.where((m) => m.name == v).firstOrNull;
}

/// Dados que permitem a outros membros de um grupo pagar-te.
@immutable
class PaymentDetails {
  const PaymentDetails({
    this.mbwayPhone = '',
    this.iban = '',
    this.ibanHolder = '',
    this.revolutTag = '',
    this.paypalUser = '',
    this.acceptsCash = true,
  });

  final String mbwayPhone;
  final String iban;
  final String ibanHolder;
  final String revolutTag;
  final String paypalUser;
  final bool acceptsCash;

  static const empty = PaymentDetails();

  bool get hasAnyDigital => mbwayPhone.isNotEmpty || iban.isNotEmpty || revolutTag.isNotEmpty || paypalUser.isNotEmpty;

  List<PaymentMethod> get methods => [
    if (mbwayPhone.isNotEmpty) PaymentMethod.mbway,
    if (iban.isNotEmpty) PaymentMethod.transfer,
    if (revolutTag.isNotEmpty) PaymentMethod.revolut,
    if (paypalUser.isNotEmpty) PaymentMethod.paypal,
    if (acceptsCash) PaymentMethod.cash,
  ];

  PaymentDetails copyWith({
    String? mbwayPhone,
    String? iban,
    String? ibanHolder,
    String? revolutTag,
    String? paypalUser,
    bool? acceptsCash,
  }) => PaymentDetails(
    mbwayPhone: mbwayPhone ?? this.mbwayPhone,
    iban: iban ?? this.iban,
    ibanHolder: ibanHolder ?? this.ibanHolder,
    revolutTag: revolutTag ?? this.revolutTag,
    paypalUser: paypalUser ?? this.paypalUser,
    acceptsCash: acceptsCash ?? this.acceptsCash,
  );

  Map<String, dynamic> toJson() => {
    'mbway_phone': mbwayPhone,
    'iban': iban,
    'iban_holder': ibanHolder,
    'revolut_tag': revolutTag,
    'paypal_user': paypalUser,
    'accepts_cash': acceptsCash,
  };

  factory PaymentDetails.fromJson(Map<String, dynamic>? j) {
    if (j == null) return empty;
    return PaymentDetails(
      mbwayPhone: j['mbway_phone'] as String? ?? '',
      iban: j['iban'] as String? ?? '',
      ibanHolder: j['iban_holder'] as String? ?? '',
      revolutTag: j['revolut_tag'] as String? ?? '',
      paypalUser: j['paypal_user'] as String? ?? '',
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

  /// Valida um IBAN com o algoritmo mod-97 (ISO 13616).
  static String? normalizeIban(String input) {
    final s = input.replaceAll(' ', '').toUpperCase();
    if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$').hasMatch(s)) return null;
    if (s.startsWith('PT') && s.length != 25) return null;
    final rearranged = s.substring(4) + s.substring(0, 4);
    var remainder = 0;
    for (final ch in rearranged.codeUnits) {
      final value = ch >= 65 ? (ch - 55).toString() : String.fromCharCode(ch);
      for (final digit in value.codeUnits) {
        remainder = (remainder * 10 + (digit - 48)) % 97;
      }
    }
    return remainder == 1 ? s : null;
  }

  static String displayIban(String s) =>
      [for (var i = 0; i < s.length; i += 4) s.substring(i, i + 4 > s.length ? s.length : i + 4)].join(' ');

  static String cleanHandle(String input) => input.trim().replaceFirst(RegExp(r'^@'), '').replaceAll(' ', '');
}
