import 'package:google_sign_in/google_sign_in.dart';

import '../core/config/env.dart';
import '../core/utils/errors.dart';

/// Conta Google: login (ID token validado pela API).
class GoogleService {
  GoogleService._();

  static final instance = GoogleService._();

  Future<void>? _init;

  GoogleSignIn get _signIn => GoogleSignIn.instance;

  Future<void> _ensureInitialized() {
    if (!Env.hasGoogle) {
      throw const AppException('O Google ainda não está configurado nesta versão da app.');
    }
    // O client ID de iOS vem do Info.plist; o Android precisa do de servidor.
    return _init ??= _signIn.initialize(serverClientId: Env.googleServerClientId);
  }

  Future<GoogleSignInAccount> _account() async {
    await _ensureInitialized();
    try {
      return await _signIn.authenticate();
    } on GoogleSignInException catch (e) {
      throw _friendly(e);
    }
  }

  /// Abre o seletor de contas e devolve o ID token para a API.
  Future<String> signIn() async {
    final account = await _account();
    final token = account.authentication.idToken;
    if (token == null) throw const AppException('O Google não devolveu os dados da conta. Tenta novamente.');
    return token;
  }

  Future<void> signOut() async {
    if (_init == null) return;
    try {
      await _signIn.signOut();
    } catch (_) {
      // Sem sessão Google local: nada a fazer.
    }
  }

  static Exception _friendly(GoogleSignInException e) => switch (e.code) {
    GoogleSignInExceptionCode.canceled => const SilentException(),
    GoogleSignInExceptionCode.clientConfigurationError || GoogleSignInExceptionCode.providerConfigurationError =>
      const AppException('O login com Google não está bem configurado nesta versão da app.'),
    _ => const AppException('Não foi possível ligar à conta Google. Tenta novamente.'),
  };
}
