import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide Person;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants.dart';
import '../core/i18n/translations.dart';
import '../core/utils/birthday_utils.dart';
import '../data/models/models.dart';
import 'reminder_copy.dart';

/// Agenda os lembretes no sistema operativo, por isso chegam mesmo com a
/// app fechada (RNF08). Sempre que os dados ou as preferências mudam, a
/// agenda é reconstruída de raiz.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String _lastSignature = '';

  /// O iOS só guarda 64 notificações pendentes; deixamos margem.
  static const _maxScheduled = 60;

  static AndroidNotificationDetails _channel({bool groupAction = false}) => AndroidNotificationDetails(
    'birthdays',
    'Aniversários',
    channelDescription: 'Lembretes de aniversários próximos',
    importance: Importance.high,
    priority: Priority.high,
    color: const Color(0xFFF05560),
    actions: groupAction
        ? const [AndroidNotificationAction(ReminderCopy.groupAction, 'Prenda em grupo', showsUserInterface: true)]
        : null,
  );

  /// Categoria do iOS com o botão "Prenda em grupo" (registada no arranque).
  static const _groupCategory = 'birthday_group';

  /// Notificações tocadas: o destino (ex.: `chat:<id>`, `person:<id>`; ver
  /// [ReminderCopy.route]).
  final _taps = StreamController<String>.broadcast();
  Stream<String> get taps => _taps.stream;

  /// Notificação que abriu a app (lida uma vez, depois de o router existir).
  String? takeLaunchPayload() {
    final p = _launchPayload;
    _launchPayload = null;
    return p;
  }

  String? _launchPayload;

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Lisbon'));
    }
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _groupCategory,
              actions: [
                DarwinNotificationAction.plain(
                  ReminderCopy.groupAction,
                  'Prenda em grupo',
                  options: {DarwinNotificationActionOption.foreground},
                ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final target = ReminderCopy.target(r.payload, r.actionId);
        if (target != null) _taps.add(target);
      },
    );
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = (launch?.didNotificationLaunchApp ?? false) ? launch!.notificationResponse : null;
      final payload = ReminderCopy.target(response?.payload, response?.actionId);
      // Se o router já está à escuta, entrega já; senão fica para takeLaunchPayload().
      if (payload != null && _taps.hasListener) {
        _taps.add(payload);
      } else {
        _launchPayload = payload;
      }
    } catch (_) {}
    _ready = true;
  }

  /// Mensagem de uma conversa. Uma notificação por conversa (a nova substitui
  /// a anterior); tocar abre a conversa.
  Future<void> showChatMessage({required String conversationId, required String title, required String body}) async {
    await init();
    if (!_ready) return;
    await _plugin.show(
      // Os lembretes usam os ids 0–59.
      id: 1000 + (conversationId.hashCode & 0x3fffffff),
      title: title,
      body: body,
      payload: 'chat:$conversationId',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'messages',
          tr(Keys.notifyChannel),
          channelDescription: tr(Keys.notifyChannelDescription),
          importance: Importance.high,
          priority: Priority.high,
          color: const Color(0xFFF05560),
          tag: conversationId,
        ),
        iOS: DarwinNotificationDetails(threadIdentifier: conversationId),
      ),
    );
  }

  Future<bool> requestPermission() async {
    await init();
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    _lastSignature = '';
    await _plugin.cancelAll();
  }

  Future<void> reschedule(AppData data, UserProfile profile) async {
    await init();
    if (!_ready) return;
    final people = data.people;

    final signature = _signature(data, profile);
    if (signature == _lastSignature) return;
    _lastSignature = signature;

    // Só os lembretes agendados: as notificações de mensagens ficam.
    await _plugin.cancelAllPendingNotifications();
    if (!profile.notificationsEnabled) return;

    final now = tz.TZDateTime.now(tz.local);
    final pending = <_Pending>[];
    for (final person in people) {
      final offsets = person.reminderDays ?? profile.defaultReminderDays;
      final next = person.nextBirthday();
      // Considera também o ano seguinte para lembretes que já passaram.
      for (final occurrence in [next, BirthdayUtils.occurrenceIn(next.year + 1, person.day, person.month)]) {
        for (final days in offsets) {
          final d = BirthdayUtils.addDays(occurrence, -days);
          final when = tz.TZDateTime(tz.local, d.year, d.month, d.day, profile.reminderHour, profile.reminderMinute);
          if (when.isAfter(now)) pending.add(_Pending(person, days, when, occurrence));
        }
      }
    }
    pending.sort((a, b) => a.when.compareTo(b.when));

    for (final (i, p) in pending.take(_maxScheduled).indexed) {
      final age = p.person.year == null ? null : p.occurrence.year - p.person.year!;
      final r = ReminderCopy.build(
        p.person,
        daysBefore: p.daysBefore,
        date: p.occurrence,
        age: age,
        hasMessage: data.messageFor(p.person.id) != null,
        ideas: data.giftsFor(p.person.id).where((g) => !g.purchased).length,
      );
      await _plugin.zonedSchedule(
        id: i,
        title: r.title,
        body: r.body,
        scheduledDate: p.when,
        payload: r.payload,
        notificationDetails: NotificationDetails(
          android: _channel(groupAction: r.groupAction),
          iOS: DarwinNotificationDetails(categoryIdentifier: r.groupAction ? _groupCategory : null),
        ),
        // Lembretes de aniversário não exigem precisão ao segundo, o que evita
        // pedir a permissão de alarmes exatos no Android.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// Muda quando muda alguma coisa que o texto dos lembretes usa (mensagem
  /// pronta, ideias por comprar).
  String _signature(AppData data, UserProfile profile) {
    final b = StringBuffer()
      ..write('${profile.notificationsEnabled}|${profile.reminderHour}:${profile.reminderMinute}|')
      ..write('${profile.defaultReminderDays}|${BirthdayUtils.today()}|');
    for (final p in data.people) {
      final ideas = data.giftsFor(p.id).where((g) => !g.purchased).length;
      b.write('${p.id}:${p.name}:${p.day}/${p.month}/${p.year}:${p.reminderDays}:${data.messageFor(p.id) != null}:$ideas;');
    }
    return b.toString();
  }
}

class _Pending {
  _Pending(this.person, this.daysBefore, this.when, this.occurrence);
  final Person person;
  final int daysBefore;
  final tz.TZDateTime when;
  final DateTime occurrence;
}
