import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/i18n/translations.dart';
import 'core/providers.dart';
import 'data/api/api_auth_repository.dart';
import 'data/api/api_client.dart';
import 'data/local/local_auth_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Datas em todas as línguas da app (as conversas seguem a língua escolhida).
  await initializeDateFormatting();
  Intl.defaultLocale = 'pt_PT';

  final prefs = await SharedPreferences.getInstance();
  // Carrega já a língua para o primeiro ecrã (a escolhida no perfil ou a do telemóvel).
  final saved = prefs.getString('velas.locale');
  await Translations.load(
    saved != null ? Locale(saved) : Translations.resolve(WidgetsBinding.instance.platformDispatcher.locales),
  );

  final api = Env.hasBackend ? ApiClient(Env.apiUrl) : null;
  final AuthRepository auth = api != null ? ApiAuthRepository(api, prefs) : LocalAuthRepository(prefs);
  await auth.init();
  unawaited(NotificationService.instance.init());

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(auth),
        apiClientProvider.overrideWithValue(api),
      ],
      child: const VelasApp(),
    ),
  );
}
