import 'dart:convert';

import 'package:aniversarios/data/api/api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object> _session(String access, String refresh) => {
  'access_token': access,
  'refresh_token': refresh,
  'expires_in': 900,
  'user': {'id': 'u1', 'email': 'a@ex.pt'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({'velas.api.refreshToken': 'r1'}));

  test('renova o access token e repete o pedido', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path} ${req.headers['Authorization'] ?? ''}');
      if (req.url.path == '/auth/refresh') {
        expect(jsonDecode(req.body), {'refresh_token': 'r1'});
        return _json(_session('a2', 'r2'));
      }
      if (req.headers['Authorization'] == 'Bearer a2') return _json({'ok': true});
      return _json({'error': 'unauthorized'}, 401);
    });
    final api = ApiClient('https://api.test/', client: client);
    await api.restore();

    expect(await api.get('/me'), {'ok': true});
    expect(calls, ['POST /auth/refresh ', 'GET /me Bearer a2']);
    expect(api.refreshToken, 'r2');
  });

  test('sessão revogada: limpa e avisa', () async {
    var expired = false;
    final client = MockClient((req) async => _json({'error': 'invalid_refresh_token'}, 401));
    final api = ApiClient('https://api.test', client: client)..onSessionExpired = () => expired = true;
    await api.restore();

    await expectLater(
      api.get('/data'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'session_expired')),
    );
    expect(expired, isTrue);
    expect(api.hasSession, isFalse);
  });

  test('converte erros da API', () async {
    final client = MockClient((req) async => _json({'error': 'username_taken', 'message': 'x'}, 409));
    final api = ApiClient('https://api.test', client: client);
    await expectLater(
      api.postPublic('/auth/signup', {}),
      throwsA(isA<ApiException>().having((e) => (e.status, e.code), 'erro', (409, 'username_taken'))),
    );
  });

  test('envia fotografias como bytes', () async {
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return _json({'photo_path': 'p'});
    });
    final api = ApiClient('https://api.test', client: client);
    await api.applySession(_session('a1', 'r1'));
    await api.putBytes('/people/1/photo', utf8.encode('img'), 'image/jpeg');
    expect(sent.headers['Content-Type'], 'image/jpeg');
    expect(sent.headers['Authorization'], 'Bearer a1');
    expect(sent.bodyBytes, utf8.encode('img'));
  });
}
