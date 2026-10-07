import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Erro devolvido pela API: `{ "error": "<código>", "message": "..." }`.
/// Os códigos são traduzidos em `friendlyError` (core/utils/errors.dart).
class ApiException implements Exception {
  const ApiException(this.status, this.code, [this.message = '']);

  final int status;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($status, $code, $message)';
}

/// Cliente HTTP da API com sessão: guarda os tokens no armazenamento seguro
/// do sistema (Keychain / Keystore) e renova o access token quando expira.
class ApiClient {
  ApiClient(String baseUrl, {http.Client? client, FlutterSecureStorage? storage})
    : _base = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
      _http = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();

  static const _refreshKey = 'velas.api.refreshToken';
  static const _timeout = Duration(seconds: 25);

  final String _base;
  final http.Client _http;
  final FlutterSecureStorage _storage;

  String? _access;
  String? _refresh;
  Future<bool>? _refreshing;

  /// Chamado quando a sessão deixa de ser válida (ex.: refresh token revogado).
  void Function()? onSessionExpired;

  bool get hasSession => _refresh != null;

  Future<void> restore() async {
    try {
      _refresh = await _storage.read(key: _refreshKey);
    } catch (_) {
      // Keychain indisponível (ex.: primeiro arranque após restauro): sem sessão.
      _refresh = null;
    }
  }

  /// Guarda a sessão de uma resposta de login e devolve o perfil (`user`).
  Future<Map<String, dynamic>> applySession(Map<String, dynamic> session) async {
    _access = session['access_token'] as String;
    _refresh = session['refresh_token'] as String;
    await _storage.write(key: _refreshKey, value: _refresh);
    return (session['user'] as Map).cast<String, dynamic>();
  }

  Future<void> clearSession() async {
    _access = null;
    _refresh = null;
    await _storage.delete(key: _refreshKey).catchError((_) {});
  }

  /// O refresh token atual (para terminar a sessão no servidor).
  String? get refreshToken => _refresh;

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body ?? const {});
  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);
  Future<dynamic> putBytes(String path, Uint8List bytes, String contentType) =>
      _send('PUT', path, bytes: bytes, contentType: contentType);

  /// Pedido sem sessão (login, registo, recuperação).
  Future<dynamic> postPublic(String path, Object body) => _send('POST', path, body: body, auth: false);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Uint8List? bytes,
    String? contentType,
    bool auth = true,
    bool retry = true,
  }) async {
    if (auth && _access == null && _refresh != null && !await _refreshSession()) {
      throw const ApiException(401, 'session_expired');
    }

    final request = http.Request(method, Uri.parse('$_base$path'));
    if (auth && _access != null) request.headers['Authorization'] = 'Bearer $_access';
    if (bytes != null) {
      request.headers['Content-Type'] = contentType ?? 'application/octet-stream';
      request.bodyBytes = bytes;
    } else if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final response = await http.Response.fromStream(await _http.send(request).timeout(_timeout));

    if (response.statusCode == 401 && auth && retry && _refresh != null) {
      if (await _refreshSession()) {
        return _send(method, path, body: body, bytes: bytes, contentType: contentType, retry: false);
      }
      throw const ApiException(401, 'session_expired');
    }

    final decoded = response.body.isEmpty ? null : _tryJson(response.body);
    if (response.statusCode >= 400) {
      final map = decoded is Map ? decoded : const {};
      throw ApiException(
        response.statusCode,
        map['error'] as String? ?? 'http_${response.statusCode}',
        map['message'] as String? ?? '',
      );
    }
    return decoded;
  }

  static Object? _tryJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// Um só pedido de renovação de cada vez, mesmo com vários pedidos em curso.
  /// `false` quando a sessão foi revogada ou expirou.
  Future<bool> _refreshSession() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final token = _refresh;
    if (token == null) return false;
    try {
      final res = await _send('POST', '/auth/refresh', body: {'refresh_token': token}, auth: false);
      await applySession((res as Map).cast<String, dynamic>());
      return true;
    } on ApiException catch (e) {
      // Outros erros (servidor em baixo, limite de pedidos) não terminam a sessão.
      if (e.status != 401) rethrow;
      await clearSession();
      onSessionExpired?.call();
      return false;
    }
  }
}
