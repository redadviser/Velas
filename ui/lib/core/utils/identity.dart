/// Regras de username, telemóvel de conta e identificação de contactos.
class Identity {
  const Identity._();

  static final _username = RegExp(r'^[a-z0-9._]{3,20}$');
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String normalizeUsername(String input) => input.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();

  /// Mensagem de erro, ou `null` se o username for válido.
  static String? usernameError(String input) {
    final u = normalizeUsername(input);
    if (u.isEmpty) return 'Escolhe um username.';
    if (u.length < 3) return 'Usa pelo menos 3 caracteres.';
    if (u.length > 20) return 'Usa no máximo 20 caracteres.';
    if (!_username.hasMatch(u)) return 'Só letras, números, ponto e underscore.';
    if (u.startsWith('.') || u.startsWith('_') || u.endsWith('.') || u.endsWith('_')) {
      return 'Não pode começar nem acabar em ponto ou underscore.';
    }
    return null;
  }

  static bool isEmail(String input) => _email.hasMatch(input.trim());

  /// Telemóvel em formato internacional (E.164). Números de 9 dígitos são
  /// assumidos como portugueses.
  static String? toE164(String input) {
    var d = input.replaceAll(RegExp(r'[\s\-().]'), '');
    if (d.startsWith('00')) d = '+${d.substring(2)}';
    if (RegExp(r'^9[1236]\d{7}$').hasMatch(d)) return '+351$d';
    if (RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(d)) {
      if (d.startsWith('+351') && !RegExp(r'^\+3519[1236]\d{7}$').hasMatch(d)) return null;
      return d;
    }
    return null;
  }

  static String displayPhone(String e164) {
    if (e164.startsWith('+351') && e164.length == 13) {
      final n = e164.substring(4);
      return '+351 ${n.substring(0, 3)} ${n.substring(3, 6)} ${n.substring(6)}';
    }
    return e164;
  }

  /// Interpreta o que a pessoa escreveu ao procurar alguém.
  static IdentifierKind kindOf(String input) {
    final t = input.trim();
    if (isEmail(t)) return IdentifierKind.email;
    if (toE164(t) != null) return IdentifierKind.phone;
    if (usernameError(t) == null) return IdentifierKind.username;
    return IdentifierKind.invalid;
  }

  /// Valor normalizado para enviar ao servidor.
  static String? normalizeIdentifier(String input) => switch (kindOf(input)) {
    IdentifierKind.email => input.trim().toLowerCase(),
    IdentifierKind.phone => toE164(input),
    IdentifierKind.username => normalizeUsername(input),
    IdentifierKind.invalid => null,
  };
}

enum IdentifierKind {
  email('email'),
  phone('telemóvel'),
  username('username'),
  invalid('');

  const IdentifierKind(this.label);
  final String label;
}
