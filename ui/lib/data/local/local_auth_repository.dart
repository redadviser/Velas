import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/errors.dart';
import '../../core/utils/identity.dart';
import '../models/models.dart';
import '../repositories/auth_repository.dart';

/// Autenticação sem servidor, para desenvolvimento.
/// As palavras-passe nunca são guardadas em texto simples: usa-se um hash
/// SHA-256 iterado com sal aleatório por utilizador.
class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository(this._prefs);

  static const _usersKey = 'velas.local.users';
  static const _sessionKey = 'velas.local.session';
  static const _iterations = 20000;

  final SharedPreferences _prefs;
  final _changes = StreamController<UserProfile?>.broadcast();
  UserProfile? _current;

  @override
  bool get isLocal => true;

  @override
  bool get supportsGoogle => false;

  @override
  UserProfile? get current => _current;

  @override
  Stream<UserProfile?> get changes async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Stream<void> get passwordRecovery => const Stream.empty();

  /// Contas criadas neste dispositivo (usadas para convidar no modo local).
  static List<UserProfile> deviceProfiles(SharedPreferences prefs) {
    final users = (jsonDecode(prefs.getString(_usersKey) ?? '{}') as Map).cast<String, dynamic>();
    return [
      for (final e in users.entries)
        UserProfile.fromJson(
          ((e.value as Map)['profile'] as Map).cast<String, dynamic>(),
          id: (e.value as Map)['id'] as String,
          email: e.key,
        ),
    ];
  }

  Map<String, dynamic> get _users => (jsonDecode(_prefs.getString(_usersKey) ?? '{}') as Map).cast<String, dynamic>();

  Future<void> _saveUsers(Map<String, dynamic> users) => _prefs.setString(_usersKey, jsonEncode(users));

  void _set(UserProfile? p) {
    _current = p;
    _changes.add(p);
  }

  UserProfile _profileOf(String email, Map<String, dynamic> record) => UserProfile.fromJson(
    (record['profile'] as Map).cast<String, dynamic>(),
    id: record['id'] as String,
    email: email,
  );

  static String _hash(String password, String salt) {
    List<int> digest = utf8.encode('$salt:$password');
    for (var i = 0; i < _iterations; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return base64Encode(digest);
  }

  static String _salt() {
    final r = Random.secure();
    return base64Encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  @override
  Future<void> init() async {
    final email = _prefs.getString(_sessionKey);
    final record = email == null ? null : _users[email];
    if (record != null) _current = _profileOf(email!, (record as Map).cast<String, dynamic>());
  }

  /// Email da conta com este email ou username.
  String? _emailFor(String identifier) {
    final users = _users;
    final id = identifier.trim().toLowerCase();
    if (users.containsKey(id)) return id;
    final username = Identity.normalizeUsername(identifier);
    for (final e in users.entries) {
      if (((e.value as Map)['profile'] as Map)['username'] == username) return e.key;
    }
    return null;
  }

  bool _taken(String field, String value, {String? exceptEmail}) =>
      value.isNotEmpty &&
      _users.entries.any((e) => e.key != exceptEmail && ((e.value as Map)['profile'] as Map)[field] == value);

  @override
  Future<({bool usernameTaken, bool phoneTaken})> checkAvailability({
    required String username,
    String phone = '',
  }) async =>
      (usernameTaken: _taken('username', Identity.normalizeUsername(username)), phoneTaken: _taken('phone', phone));

  @override
  Future<void> signIn({required String identifier, required String password}) async {
    final key = _emailFor(identifier);
    final record = key == null ? null : (_users[key] as Map?)?.cast<String, dynamic>();
    if (record == null || _hash(password, record['salt'] as String) != record['hash']) {
      throw const AppException('Dados de acesso incorretos.');
    }
    await _prefs.setString(_sessionKey, key!);
    _set(_profileOf(key, record));
  }

  @override
  Future<void> signInWithGoogle() async {
    throw const AppException('O login com Google precisa do servidor da Velas.');
  }

  @override
  Future<bool> handleAuthLink(Uri uri) async => false;

  @override
  Future<SignUpResult> signUp({
    required String name,
    required String username,
    required String email,
    required String password,
    String phone = '',
  }) async {
    final key = email.trim().toLowerCase();
    final users = _users;
    if (users.containsKey(key)) throw const AppException('Já existe uma conta com este email.');
    final u = Identity.normalizeUsername(username);
    if (_taken('username', u)) throw const AppException('Este username já está a ser usado.');
    if (_taken('phone', phone)) throw const AppException('Este telemóvel já está associado a outra conta.');
    final salt = _salt();
    final id = const Uuid().v4();
    final profile = UserProfile(id: id, email: key, name: name.trim(), username: u, phone: phone);
    users[key] = {'id': id, 'salt': salt, 'hash': _hash(password, salt), 'profile': profile.toPrefsJson()};
    await _saveUsers(users);
    await _prefs.setString(_sessionKey, key);
    _set(profile);
    return SignUpResult.signedIn;
  }

  @override
  Future<void> signOut() async {
    await _prefs.remove(_sessionKey);
    _set(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    throw const AppException(
      'No modo local não é possível enviar emails. Liga a app ao servidor (API_URL) para ativar a recuperação de palavra-passe.',
    );
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    final p = _current;
    if (p == null) return;
    final users = _users;
    final record = (users[p.email] as Map).cast<String, dynamic>();
    final salt = _salt();
    users[p.email] = {...record, 'salt': salt, 'hash': _hash(newPassword, salt)};
    await _saveUsers(users);
  }

  @override
  Future<void> updateProfile(UserProfile profile) async {
    if (_taken('username', profile.username, exceptEmail: profile.email)) {
      throw const AppException('Este username já está a ser usado.');
    }
    if (_taken('phone', profile.phone, exceptEmail: profile.email)) {
      throw const AppException('Este telemóvel já está associado a outra conta.');
    }
    final users = _users;
    final record = (users[profile.email] as Map).cast<String, dynamic>();
    users[profile.email] = {...record, 'profile': profile.toPrefsJson()};
    await _saveUsers(users);
    _set(profile);
  }

  @override
  Future<void> deleteAccount() async {
    final p = _current;
    if (p == null) return;
    final users = _users..remove(p.email);
    await _saveUsers(users);
    await _prefs.remove('velas.local.data.${p.id}');
    await signOut();
  }
}
