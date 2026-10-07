import '../models/models.dart';

enum SignUpResult { signedIn, needsEmailConfirmation }

/// Contrato de autenticação. Existem duas implementações: API (produção,
/// pasta `backend`) e local (sem servidor).
abstract class AuthRepository {
  bool get isLocal;

  /// Se o botão "Continuar com Google" deve aparecer.
  bool get supportsGoogle;

  UserProfile? get current;

  /// Emite o utilizador atual sempre que a sessão ou o perfil mudam.
  Stream<UserProfile?> get changes;

  /// Emite quando o utilizador abre o link de recuperação de palavra-passe.
  Stream<void> get passwordRecovery;

  Future<void> init();

  /// [identifier] é o email ou o username.
  Future<void> signIn({required String identifier, required String password});

  /// Entra com a conta Google; cria a conta se ainda não existir.
  Future<void> signInWithGoogle();

  /// [phone] em formato E.164, ou vazio.
  Future<SignUpResult> signUp({
    required String name,
    required String username,
    required String email,
    required String password,
    String phone = '',
  });

  /// Verifica se o username e o telemóvel ainda estão livres.
  Future<({bool usernameTaken, bool phoneTaken})> checkAvailability({required String username, String phone = ''});

  Future<void> signOut();

  Future<void> sendPasswordReset(String email);

  /// Trata um link de autenticação que abriu a app (ex.: recuperação de
  /// palavra-passe). Devolve `true` se o link era deste tipo.
  Future<bool> handleAuthLink(Uri uri);

  Future<void> updatePassword(String newPassword);

  Future<void> updateProfile(UserProfile profile);

  /// Elimina a conta e todos os dados associados (direito ao apagamento, RGPD).
  Future<void> deleteAccount();
}
