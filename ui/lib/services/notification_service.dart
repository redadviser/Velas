import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide Person;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../core/config/env.dart';
import '../core/constants.dart';
import '../core/i18n/translations.dart';
import '../core/utils/birthday_utils.dart';
import '../data/models/models.dart';
import 'reminder_copy.dart';

/// Botão "Responder" (com texto) e "Marcar como lida" das notificações de mensagens.
const chatReplyAction = 'chat_reply';
const chatReadAction = 'chat_read';

/// Uma notificação de mensagem: a conversa e, vinda do push, o token que deixa
/// responder sem abrir a app (`chat:<id>|<token>`).
({String conversationId, String? token})? chatPayloadOf(String? payload) {
  if (payload == null || !payload.startsWith('chat:')) return null;
  final rest = payload.substring(5);
  final bar = rest.indexOf('|');
  return bar < 0
      ? (conversationId: rest, token: null)
      : (conversationId: rest.substring(0, bar), token: rest.substring(bar + 1));
}

/// Responder ou marcar como lida com o token da notificação (POST /push/reply,
/// /push/read). Não usa a sessão: corre também com a app fechada.
Future<void> answerWithToken(String token, {String? reply}) async {
  final base = Env.apiUrl.replaceFirst(RegExp(r'/+$'), '');
  final res = await http.post(
    Uri.parse(reply == null ? '$base/push/read' : '$base/push/reply'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'token': token,
      if (reply != null) ...{'id': const Uuid().v4(), 'body': reply},
    }),
  );
  if (res.statusCode >= 400) throw HttpException('push ${res.statusCode}');
}

/// "Responder" tocado com a app fechada (Android): corre num isolate à parte.
@pragma('vm:entry-point')
Future<void> notificationBackgroundResponse(NotificationResponse r) async {
  final chat = chatPayloadOf(r.payload);
  if (chat?.token == null) return;
  final text = r.input?.trim() ?? '';
  try {
    if (r.actionId == chatReplyAction && text.isNotEmpty) {
      await answerWithToken(chat!.token!, reply: text);
    } else if (r.actionId == chatReadAction) {
      await answerWithToken(chat!.token!);
    }
  } catch (_) {
    // Sem rede: a mensagem perde-se como num envio falhado; a notificação já foi fechada.
  }
}

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

  /// Semanas de resumo agendadas à frente (Birthdayly+), com os ids 900 em diante.
  static const _digestWeeks = 4;

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

  /// Categoria do iOS das mensagens ("Responder", "Marcar como lida"); o push usa a mesma.
  static const _chatCategory = 'chat_message';

  /// Mensagens agendadas para enviar fora da app: ids 700 em diante.
  static const _scheduledBase = 700;

  /// Responder ou marcar como lida uma notificação que não veio do push (a app
  /// estava aberta e a mensagem chegou pelo WebSocket): usa a sessão da app.
  Future<void> Function(String conversationId, String text)? onChatReply;
  Future<void> Function(String conversationId)? onChatRead;

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

  /// Abrir um destino vindo de fora (ex.: notificação do push tocada no iOS).
  void openTarget(String target) {
    if (_taps.hasListener) {
      _taps.add(target);
    } else {
      _launchPayload = target;
    }
  }

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
        android: const AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _chatCategory,
              actions: [
                DarwinNotificationAction.text(
                  chatReplyAction,
                  tr(Keys.notifyReply),
                  buttonTitle: tr(Keys.notifySend),
                  placeholder: tr(Keys.notifyReplyHint),
                ),
                DarwinNotificationAction.plain(chatReadAction, tr(Keys.notifyMarkRead)),
              ],
            ),
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
        if (r.actionId == chatReplyAction || r.actionId == chatReadAction) {
          unawaited(_answer(r));
          return;
        }
        final target = ReminderCopy.target(r.payload, r.actionId);
        if (target != null) _taps.add(target);
      },
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundResponse,
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

  /// "Responder" / "Marcar como lida" com a app aberta: com o token do push,
  /// ou pela sessão da app (notificações vindas do WebSocket).
  Future<void> _answer(NotificationResponse r) async {
    final chat = chatPayloadOf(r.payload);
    if (chat == null) return;
    final text = r.input?.trim() ?? '';
    try {
      if (r.actionId == chatReplyAction) {
        if (text.isEmpty) return;
        if (chat.token != null) {
          await answerWithToken(chat.token!, reply: text);
        } else {
          await onChatReply?.call(chat.conversationId, text);
        }
      } else if (chat.token != null) {
        await answerWithToken(chat.token!);
      } else {
        await onChatRead?.call(chat.conversationId);
      }
    } catch (_) {}
  }

  static int _chatId(String conversationId) => 1000 + (conversationId.hashCode & 0x3fffffff);

  /// Mensagem de uma conversa. Uma notificação por conversa (a nova substitui
  /// a anterior); tocar abre a conversa; "Responder" escreve sem abrir a app.
  /// [replyToken] vem do push e deixa responder mesmo com a app fechada.
  Future<void> showChatMessage({
    required String conversationId,
    required String title,
    required String body,
    String? replyToken,
  }) async {
    await init();
    if (!_ready) return;
    await _plugin.show(
      // Os lembretes usam os ids 0–59.
      id: _chatId(conversationId),
      title: title,
      body: body,
      payload: replyToken == null ? 'chat:$conversationId' : 'chat:$conversationId|$replyToken',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'messages',
          tr(Keys.notifyChannel),
          channelDescription: tr(Keys.notifyChannelDescription),
          importance: Importance.high,
          priority: Priority.high,
          color: const Color(0xFFF05560),
          tag: conversationId,
          category: AndroidNotificationCategory.message,
          actions: [
            AndroidNotificationAction(
              chatReplyAction,
              tr(Keys.notifyReply),
              inputs: [AndroidNotificationActionInput(label: tr(Keys.notifyReplyHint))],
              // Responde sem abrir a app (ver notificationBackgroundResponse).
              showsUserInterface: false,
              allowGeneratedReplies: true,
            ),
            AndroidNotificationAction(chatReadAction, tr(Keys.notifyMarkRead), showsUserInterface: false),
          ],
        ),
        iOS: DarwinNotificationDetails(threadIdentifier: conversationId, categoryIdentifier: _chatCategory),
      ),
    );
  }

  /// Uma notificação simples vinda do push (ex.: "Enviámos os teus parabéns").
  Future<void> showInfo({required String title, required String body, required String payload}) async {
    await init();
    if (!_ready) return;
    await _plugin.show(
      id: 2000 + (payload.hashCode & 0x3fffffff),
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(android: _channel(), iOS: const DarwinNotificationDetails()),
    );
  }

  /// Uma mensagem do push (FCM), com a app aberta ou fechada (Android: o push
  /// traz só os dados e a notificação é desenhada aqui, com "Responder").
  Future<void> showPush(Map<String, dynamic> data) async {
    final title = data['title'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    switch (data['type']) {
      case 'chat':
        final id = data['conversation_id'] as String?;
        if (id == null) return;
        await showChatMessage(conversationId: id, title: title, body: body, replyToken: data['reply_token'] as String?);
      case 'scheduled_sent' || 'scheduled_failed':
        await showInfo(title: title, body: body, payload: 'message:${data['person_id']}');
    }
  }

  /// A conversa foi aberta na app: tira a notificação dela.
  Future<void> clearChat(String conversationId) async {
    if (!_ready) return;
    await _plugin.cancel(id: _chatId(conversationId), tag: conversationId);
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
    final digest = profile.isPlus && profile.weeklyDigest;
    final pending = <_Pending>[];
    for (final person in people) {
      final offsets = person.reminderDays ?? profile.defaultReminderDays;
      // Hora própria da pessoa (Birthdayly+); senão a do perfil.
      final custom = profile.isPlus && person.reminderHour != null && person.reminderMinute != null;
      final hour = custom ? person.reminderHour! : profile.reminderHour;
      final minute = custom ? person.reminderMinute! : profile.reminderMinute;
      final next = person.nextBirthday();
      // Considera também o ano seguinte para lembretes que já passaram.
      for (final occurrence in [next, BirthdayUtils.occurrenceIn(next.year + 1, person.day, person.month)]) {
        for (final days in offsets) {
          final d = BirthdayUtils.addDays(occurrence, -days);
          final when = tz.TZDateTime(tz.local, d.year, d.month, d.day, hour, minute);
          if (when.isAfter(now)) pending.add(_Pending(person, days, when, occurrence));
        }
      }
    }
    pending.sort((a, b) => a.when.compareTo(b.when));

    // Mensagens agendadas para enviar fora da app: o aviso à hora marcada.
    final sends = [
      for (final m in data.messages)
        if (m.scheduleVia == ScheduleVia.remind && m.scheduledAt != null && m.scheduledAt!.isAfter(now))
          if (data.person(m.personId) case final person?) (person, m),
    ]..sort((a, b) => a.$2.scheduledAt!.compareTo(b.$2.scheduledAt!));
    final scheduledSends = sends.take(10).toList();
    for (final (i, (person, m)) in scheduledSends.indexed) {
      final r = ReminderCopy.scheduledSend(person, m);
      await _plugin.zonedSchedule(
        id: _scheduledBase + i,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime.from(m.scheduledAt!, tz.local),
        payload: r.payload,
        notificationDetails: NotificationDetails(android: _channel(), iOS: const DarwinNotificationDetails()),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }

    // O resumo semanal e as mensagens agendadas ocupam lugares (o iOS só guarda 64 notificações).
    final room = _maxScheduled - scheduledSends.length - (digest ? _digestWeeks : 0);
    for (final (i, p) in pending.take(room).indexed) {
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

    if (digest) {
      // As próximas segundas-feiras, à hora dos lembretes.
      final today = DateTime(now.year, now.month, now.day);
      var monday = today.add(Duration(days: (DateTime.monday - today.weekday) % 7));
      for (var w = 0; w < _digestWeeks; w++, monday = monday.add(const Duration(days: 7))) {
        final when = tz.TZDateTime(
          tz.local,
          monday.year,
          monday.month,
          monday.day,
          profile.reminderHour,
          profile.reminderMinute,
        );
        if (!when.isAfter(now)) continue;
        final d = ReminderCopy.weeklyDigest(people, monday);
        if (d == null) continue;
        await _plugin.zonedSchedule(
          id: 900 + w,
          title: d.title,
          body: d.body,
          scheduledDate: when,
          payload: d.payload,
          notificationDetails: NotificationDetails(android: _channel(), iOS: const DarwinNotificationDetails()),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }
  }

  /// Muda quando muda alguma coisa que o texto dos lembretes usa (mensagem
  /// pronta, ideias por comprar).
  String _signature(AppData data, UserProfile profile) {
    final b = StringBuffer()
      ..write('${profile.notificationsEnabled}|${profile.reminderHour}:${profile.reminderMinute}|')
      ..write('${profile.defaultReminderDays}|${BirthdayUtils.today()}|')
      ..write('${profile.isPlus}|${profile.weeklyDigest}|');
    for (final p in data.people) {
      final ideas = data.giftsFor(p.id).where((g) => !g.purchased).length;
      b.write(
        '${p.id}:${p.name}:${p.day}/${p.month}/${p.year}:${p.reminderDays}:${p.reminderHour}:${p.reminderMinute}:'
        '${data.messageFor(p.id) != null}:$ideas;',
      );
    }
    for (final m in data.messages) {
      if (m.scheduleVia == ScheduleVia.remind) b.write('send:${m.id}:${m.scheduledAt}:${m.body.hashCode};');
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
