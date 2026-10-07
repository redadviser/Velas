import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide Person;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/utils/birthday_utils.dart';
import '../data/models/models.dart';

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

  static const _channel = AndroidNotificationDetails(
    'birthdays',
    'Aniversários',
    channelDescription: 'Lembretes de aniversários próximos',
    importance: Importance.high,
    priority: Priority.high,
    color: Color(0xFFF05560),
  );

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
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
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

  Future<void> reschedule(List<Person> people, UserProfile profile) async {
    await init();
    if (!_ready) return;

    final signature = _signature(people, profile);
    if (signature == _lastSignature) return;
    _lastSignature = signature;

    await _plugin.cancelAll();
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
      final (title, body) = _copy(p.person, p.daysBefore, age, p.occurrence);
      await _plugin.zonedSchedule(
        id: i,
        title: title,
        body: body,
        scheduledDate: p.when,
        payload: p.person.id,
        notificationDetails: const NotificationDetails(android: _channel, iOS: DarwinNotificationDetails()),
        // Lembretes de aniversário não exigem precisão ao segundo, o que evita
        // pedir a permissão de alarmes exatos no Android.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  (String, String) _copy(Person p, int daysBefore, int? age, DateTime date) {
    final ageText = age == null ? '' : ' Faz $age anos.';
    return switch (daysBefore) {
      0 => ('🎂 Hoje é o aniversário de ${p.firstName}', 'Não te esqueças de lhe dar os parabéns!$ageText'),
      1 => ('${p.name} faz anos amanhã', '${Fmt.dayMonth(date)}.$ageText Já tens a mensagem pronta?'),
      _ => (
        '${p.name} faz anos daqui a ${reminderShortLabel(daysBefore)}',
        '${Fmt.weekdayDayMonth(date)}.$ageText Ainda vais a tempo de tratar do presente.',
      ),
    };
  }

  String _signature(List<Person> people, UserProfile profile) {
    final b = StringBuffer()
      ..write('${profile.notificationsEnabled}|${profile.reminderHour}:${profile.reminderMinute}|')
      ..write('${profile.defaultReminderDays}|${BirthdayUtils.today()}|');
    for (final p in people) {
      b.write('${p.id}:${p.name}:${p.day}/${p.month}/${p.year}:${p.reminderDays};');
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
