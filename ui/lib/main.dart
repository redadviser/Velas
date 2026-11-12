import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
  // As letras vêm em assets/google_fonts: sem rede no primeiro arranque não cai para a Roboto.
  GoogleFonts.config.allowRuntimeFetching = false;
  // Carregar antes do primeiro ecrã: alguns widgets (ex.: chips) medem o texto com a letra
  // de reserva e não voltam a medir, ficando cortados.
  await GoogleFonts.pendingFonts([
    for (final w in [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800])
      GoogleFonts.dmSans(fontWeight: w),
    GoogleFonts.nunito(fontWeight: FontWeight.w900),
  ]);
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in [('DM Sans', 'OFL-DMSans.txt'), ('Nunito', 'OFL-Nunito.txt')]) {
      yield LicenseEntryWithLineBreaks([family], await rootBundle.loadString('assets/google_fonts/$file'));
    }
  });

  final prefs = await SharedPreferences.getInstance();
  // Carrega já a língua para o primeiro ecrã (a escolhida no perfil ou a do telemóvel).
  final saved = prefs.getString('velas.locale');
  await Translations.load(
    (saved == null ? null : Translations.localeOf(saved)) ?? Translations.resolve(WidgetsBinding.instance.platformDispatcher.locales),
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
