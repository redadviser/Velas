import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/providers.dart';
import 'data/api/api_auth_repository.dart';
import 'data/api/api_client.dart';
import 'data/local/local_auth_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_PT');
  Intl.defaultLocale = 'pt_PT';

  final prefs = await SharedPreferences.getInstance();

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
