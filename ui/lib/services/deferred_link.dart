import 'dart:io';

import 'package:flutter/services.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/cards/card_links.dart';

/// Cartão que levou a pessoa a instalar a app, procurado só na primeira
/// abertura (ver backend/src/modules/cards/card-page.routes.ts):
/// * Android: o referrer da Play Store (`card=TOKEN`);
/// * iPhone: o link do cartão, copiado pela página antes de ir para a App Store.
class DeferredLink {
  const DeferredLink._();

  static const _key = 'velas.deferredLinkChecked';

  static Future<String?> takeCardToken(SharedPreferences prefs) async {
    if (prefs.getBool(_key) ?? false) return null;
    await prefs.setBool(_key, true);
    try {
      if (Platform.isAndroid) {
        final referrer = (await PlayInstallReferrer.installReferrer).installReferrer;
        return referrer == null ? null : CardLinks.tokenFromReferrer(referrer);
      }
      // Ver se há texto não mostra o aviso de "colar" do iOS; só lê-lo.
      if (Platform.isIOS && await Clipboard.hasStrings()) {
        final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
        return text == null ? null : CardLinks.tokenFromText(text);
      }
    } catch (_) {
      // Sem Play Store, área de transferência indisponível, ...: segue sem cartão.
    }
    return null;
  }
}
