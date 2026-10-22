import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/i18n/translations.dart';
import 'notification_service.dart';

/// O projeto Firebase (Definições do projeto → As tuas apps), passado no build
/// com `--dart-define-from-file=.env` (ver `.env.example`). Sem ele não há push.
class FirebaseConfig {
  const FirebaseConfig._();

  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _androidApiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  static const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const _iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');

  static FirebaseOptions? get options {
    if (kIsWeb || _projectId.isEmpty || _senderId.isEmpty) return null;
    final (apiKey, appId) = Platform.isAndroid
        ? (_androidApiKey, _androidAppId)
        : Platform.isIOS
        ? (_iosApiKey, _iosAppId)
        : ('', '');
    if (apiKey.isEmpty || appId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      iosBundleId: Platform.isIOS ? 'com.velas.app' : null,
    );
  }
}

/// Push com a app em segundo plano ou fechada (Android: o push traz só dados e
/// a notificação, com "Responder", é desenhada aqui). Corre num isolate à parte.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage message) async {
  // No iOS o próprio sistema mostra a notificação do push.
  if (Platform.isIOS) return;
  await Firebase.initializeApp(options: FirebaseConfig.options);
  try {
    // Os botões na língua da app.
    final saved = (await SharedPreferences.getInstance()).getString('velas.locale');
    await Translations.load(saved != null ? Locale(saved) : Translations.resolve(PlatformDispatcher.instance.locales));
  } catch (_) {}
  await NotificationService.instance.showPush(message.data);
}

/// Notificações push (Firebase Cloud Messaging): o token deste telemóvel e as
/// mensagens que chegam com a app aberta, em segundo plano ou fechada.
class PushService {
  PushService._();
  static final instance = PushService._();

  bool _started = false;

  /// O token atual deste telemóvel (para o registar na API e retirar ao sair).
  String? token;
  final _tokens = StreamController<String>.broadcast();

  /// Token novo (o Firebase pode trocá-lo).
  Stream<String> get tokens => _tokens.stream;

  bool get available => FirebaseConfig.options != null;

  /// Arranca uma vez. [socketConnected]: com o WebSocket ligado, as mensagens
  /// já chegam por ele (e a notificação já foi mostrada).
  Future<void> start({required bool Function() socketConnected}) async {
    if (_started || !available) return;
    _started = true;
    try {
      await Firebase.initializeApp(options: FirebaseConfig.options);
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessage);
      final fm = FirebaseMessaging.instance;

      FirebaseMessaging.onMessage.listen((m) {
        if (m.data['type'] == 'chat' && socketConnected()) return;
        unawaited(NotificationService.instance.showPush(_withText(m)));
      });
      // iOS: tocou na notificação do sistema.
      FirebaseMessaging.onMessageOpenedApp.listen(_open);
      final initial = await fm.getInitialMessage();
      if (initial != null) _open(initial);

      // O token clássico (o que a API HTTP v1 do FCM recebe em `token`). O
      // register()/onRegistered novo dá o ID da instalação, para outro tipo de envio.
      // ignore: deprecated_member_use
      fm.onTokenRefresh.listen(_setToken);
      // iOS: o token só existe depois do token APNs (pode demorar uns segundos).
      for (var attempt = 0; attempt < 5 && token == null; attempt++) {
        try {
          // ignore: deprecated_member_use
          final t = await fm.getToken();
          if (t != null) _setToken(t);
        } catch (_) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    } catch (_) {
      // Sem Google Play Services ou sem configuração válida: fica sem push.
    }
  }

  void _setToken(String t) {
    token = t;
    _tokens.add(t);
  }

  /// No iOS o título e o texto vêm na parte "notification" do push.
  static Map<String, dynamic> _withText(RemoteMessage m) => {
    ...m.data,
    if (m.notification?.title != null) 'title': m.notification!.title,
    if (m.notification?.body != null) 'body': m.notification!.body,
  };

  void _open(RemoteMessage m) {
    final d = m.data;
    final target = switch (d['type']) {
      'chat' => 'chat:${d['conversation_id']}',
      'scheduled_sent' || 'scheduled_failed' => 'message:${d['person_id']}',
      _ => null,
    };
    if (target != null) NotificationService.instance.openTarget(target);
  }
}
