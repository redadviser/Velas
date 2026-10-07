import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/env.dart';
import '../../core/utils/identity.dart';
import '../../services/google_service.dart';
import '../models/models.dart';
import '../repositories/auth_repository.dart';
import 'api_client.dart';

/// Autenticação na API própria (pasta `backend`): email ou username com
/// palavra-passe, ou conta Google.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api, this._prefs) {
    _api.onSessionExpired = () => _set(null);
  }

  /// Último perfil conhecido, para a app abrir sem rede.
  static const _profileKey = 'velas.api.profile';

  final ApiClient _api;
  final SharedPreferences _prefs;
  final _changes = StreamController<UserProfile?>.broadcast();
  final _recovery = StreamController<void>.broadcast();
  UserProfile? _current;

  @override
  bool get isLocal => false;

  @override
  bool get supportsGoogle => Env.hasGoogle;

  @override
  UserProfile? get current => _current;

  @override
  Stream<UserProfile?> get changes async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Stream<void> get passwordRecovery => _recovery.stream;

  static UserProfile _profile(Map<String, dynamic> j) =>
      UserProfile.fromJson(j, id: j['id'] as String, email: j['email'] as String? ?? '');

  void _set(UserProfile? profile, [Map<String, dynamic>? json]) {
    _current = profile;
    if (profile == null) {
      _prefs.remove(_profileKey);
    } else if (json != null) {
      _prefs.setString(_profileKey, jsonEncode(json));
    }
    _changes.add(profile);
  }

  Future<void> _applySession(Object? response) async {
    final json = await _api.applySession((response as Map).cast<String, dynamic>());
    _set(_profile(json), json);
  }

  @override
  Future<void> init() async {
    await _api.restore();
    if (!_api.hasSession) return;
    try {
      final json = ((await _api.get('/me')) as Map).cast<String, dynamic>();
      _current = _profile(json);
      await _prefs.setString(_profileKey, jsonEncode(json));
    } on ApiException {
      // Sessão inválida: começa sem utilizador.
      await _api.clearSession();
      await _prefs.remove(_profileKey);
    } catch (_) {
      // Sem rede: entra com o último perfil conhecido e sincroniza mais tarde.
      final cached = _prefs.getString(_profileKey);
      if (cached != null) _current = _profile((jsonDecode(cached) as Map).cast<String, dynamic>());
    }
  }

  @override
  Future<void> signIn({required String identifier, required String password}) async {
    final id = Identity.isEmail(identifier) ? identifier.trim() : Identity.normalizeUsername(identifier);
    await _applySession(await _api.postPublic('/auth/login', {'identifier': id, 'password': password}));
  }

  @override
  Future<void> signInWithGoogle() async {
    final idToken = await GoogleService.instance.signIn();
    await _applySession(await _api.postPublic('/auth/google', {'id_token': idToken}));
  }

  @override
  Future<({bool usernameTaken, bool phoneTaken})> checkAvailability({
    required String username,
    String phone = '',
  }) async {
    final res = await _api.postPublic('/auth/signup-check', {
      'username': Identity.normalizeUsername(username),
      'phone': phone.isEmpty ? null : phone,
    });
    final m = (res as Map).cast<String, dynamic>();
    return (usernameTaken: m['username_taken'] == true, phoneTaken: m['phone_taken'] == true);
  }

  @override
  Future<SignUpResult> signUp({
    required String name,
    required String username,
    required String email,
    required String password,
    String phone = '',
  }) async {
    await _applySession(
      await _api.postPublic('/auth/signup', {
        'name': name.trim(),
        'username': Identity.normalizeUsername(username),
        'email': email.trim(),
        'password': password,
        if (phone.isNotEmpty) 'phone': phone,
      }),
    );
    return SignUpResult.signedIn;
  }

  @override
  Future<void> signOut() async {
    final token = _api.refreshToken;
    if (token != null) {
      // Termina a sessão no servidor; sem rede basta esquecê-la aqui.
      await _api.postPublic('/auth/logout', {'refresh_token': token}).catchError((_) => null);
    }
    await _api.clearSession();
    await GoogleService.instance.signOut();
    _set(null);
  }

  @override
  Future<void> sendPasswordReset(String email) => _api.postPublic('/auth/password/forgot', {'email': email.trim()});

  /// Link do email de recuperação: `com.eupasoft.velas://auth-callback?type=recovery&token=...`.
  @override
  Future<bool> handleAuthLink(Uri uri) async {
    final token = uri.queryParameters['token'];
    if (uri.host != 'auth-callback' || uri.queryParameters['type'] != 'recovery' || token == null) return false;
    await _applySession(await _api.postPublic('/auth/password/recover', {'token': token}));
    _recovery.add(null);
    return true;
  }

  @override
  Future<void> updatePassword(String newPassword) => _api.put('/me/password', {'password': newPassword});

  @override
  Future<void> updateProfile(UserProfile profile) async {
    final json = ((await _api.patch('/me', profile.toPrefsJson())) as Map).cast<String, dynamic>();
    _set(_profile(json), json);
  }

  @override
  Future<void> deleteAccount() async {
    await _api.delete('/me');
    await _api.clearSession();
    await GoogleService.instance.signOut();
    _set(null);
  }
}
