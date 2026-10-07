import 'package:google_sign_in/google_sign_in.dart';

import '../core/config/env.dart';
import '../core/utils/errors.dart';

/// Conta Google: login (ID token validado pela API) e autorização para ler
/// os contactos (People API).
class GoogleService {
  GoogleService._();

  static final instance = GoogleService._();

  static const contactsScope = 'https://www.googleapis.com/auth/contacts.readonly';

  Future<void>? _init;

  GoogleSignIn get _signIn => GoogleSignIn.instance;

  Future<void> _ensureInitialized() {
    if (!Env.hasGoogle) {
      throw const AppException('O Google ainda não está configurado nesta versão da app.');
    }
    // O client ID de iOS vem do Info.plist; o Android precisa do de servidor.
    return _init ??= _signIn.initialize(serverClientId: Env.googleServerClientId);
  }

  Future<GoogleSignInAccount> _account({List<String> scopeHint = const []}) async {
    await _ensureInitialized();
    try {
      return await _signIn.authenticate(scopeHint: scopeHint);
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

  /// Token de acesso de curta duração só para ler contactos. Pede
  /// autorização na primeira vez.
  Future<String> contactsAccessToken() async {
    final account = await _account(scopeHint: const [contactsScope]);
    try {
      final authz =
          await account.authorizationClient.authorizationForScopes(const [contactsScope]) ??
          await account.authorizationClient.authorizeScopes(const [contactsScope]);
      return authz.accessToken;
    } on GoogleSignInException catch (e) {
      throw _friendly(e);
    }
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
