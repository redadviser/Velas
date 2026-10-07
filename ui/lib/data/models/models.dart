import 'package:flutter/foundation.dart';

import '../../core/utils/birthday_utils.dart';
import 'payment.dart';

export 'payment.dart';

/// Antecedências de lembrete disponíveis (em dias antes do aniversário).
const kReminderOptions = <int>[0, 1, 3, 7, 14];
const kDefaultReminderDays = <int>[0, 1];

String reminderLabel(int days) => switch (days) {
  0 => 'No próprio dia',
  1 => '1 dia antes',
  7 => '1 semana antes',
  14 => '2 semanas antes',
  _ => '$days dias antes',
};

String reminderShortLabel(int days) => switch (days) {
  0 => 'No dia',
  1 => '1 dia',
  7 => '1 semana',
  14 => '2 semanas',
  _ => '$days dias',
};

List<int> _intList(dynamic v) => v == null ? const [] : (v as List).map((e) => (e as num).toInt()).toList();
double? _double(dynamic v) => v == null ? null : (v as num).toDouble();
DateTime _date(dynamic v) => v == null ? DateTime.now() : DateTime.parse(v as String).toLocal();

@immutable
class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.name,
    this.username = '',
    this.phone = '',
    this.notificationsEnabled = true,
    this.reminderHour = 9,
    this.reminderMinute = 0,
    this.defaultReminderDays = kDefaultReminderDays,
    this.payment = PaymentDetails.empty,
  });

  final String id;
  final String email;
  final String name;

  /// Único, em minúsculas. Vazio em contas antigas que ainda não o definiram.
  final String username;

  /// Formato E.164 (+351…). Opcional.
  final String phone;
  final bool notificationsEnabled;
  final int reminderHour;
  final int reminderMinute;
  final List<int> defaultReminderDays;

  /// Privados: só são revelados aos membros de um grupo em que és o comprador.
  final PaymentDetails payment;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  UserProfile copyWith({
    String? name,
    String? username,
    String? phone,
    bool? notificationsEnabled,
    int? reminderHour,
    int? reminderMinute,
    List<int>? defaultReminderDays,
    PaymentDetails? payment,
  }) => UserProfile(
    id: id,
    email: email,
    name: name ?? this.name,
    username: username ?? this.username,
    phone: phone ?? this.phone,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    reminderHour: reminderHour ?? this.reminderHour,
    reminderMinute: reminderMinute ?? this.reminderMinute,
    defaultReminderDays: defaultReminderDays ?? this.defaultReminderDays,
    payment: payment ?? this.payment,
  );

  Map<String, dynamic> toPrefsJson() => {
    'display_name': name,
    'username': username.isEmpty ? null : username,
    'phone': phone.isEmpty ? null : phone,
    'notifications_enabled': notificationsEnabled,
    'reminder_hour': reminderHour,
    'reminder_minute': reminderMinute,
    'default_reminder_days': defaultReminderDays,
    'payment_methods': payment.toJson(),
  };

  factory UserProfile.fromJson(Map<String, dynamic> j, {required String id, required String email}) => UserProfile(
    id: id,
    email: email,
    name: (j['display_name'] as String?)?.trim().isNotEmpty == true
        ? j['display_name'] as String
        : email.split('@').first,
    username: j['username'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    notificationsEnabled: j['notifications_enabled'] as bool? ?? true,
    reminderHour: (j['reminder_hour'] as num?)?.toInt() ?? 9,
    reminderMinute: (j['reminder_minute'] as num?)?.toInt() ?? 0,
    defaultReminderDays: j['default_reminder_days'] == null
        ? kDefaultReminderDays
        : _intList(j['default_reminder_days']),
    payment: PaymentDetails.fromJson((j['payment_methods'] as Map?)?.cast<String, dynamic>()),
  );
}

@immutable
class PersonCategory {
  const PersonCategory({required this.id, required this.name, required this.color, this.sort = 0});

  final String id;
  final String name;

  /// Índice em [AppColors.swatches].
  final int color;
  final int sort;

  PersonCategory copyWith({String? name, int? color, int? sort}) =>
      PersonCategory(id: id, name: name ?? this.name, color: color ?? this.color, sort: sort ?? this.sort);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color, 'sort': sort};

  factory PersonCategory.fromJson(Map<String, dynamic> j) => PersonCategory(
    id: j['id'] as String,
    name: j['name'] as String,
    color: (j['color'] as num?)?.toInt() ?? 0,
    sort: (j['sort'] as num?)?.toInt() ?? 0,
  );
}

@immutable
class Person {
  const Person({
    required this.id,
    required this.name,
    required this.day,
    required this.month,
    this.year,
    this.relation = '',
    this.categoryId,
    this.photoPath,
    this.photoUrl,
    this.notes = '',
    this.giftBudget,
    this.reminderDays,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int day;
  final int month;

  /// Opcional: muitas pessoas sabem o dia mas não o ano.
  final int? year;
  final String relation;
  final String? categoryId;

  /// Caminho persistido (storage remoto ou ficheiro local).
  final String? photoPath;

  /// URL pronto a mostrar (assinado e temporário, no caso da API). Não é persistido.
  final String? photoUrl;
  final String notes;
  final double? giftBudget;

  /// `null` significa "usar as preferências do utilizador".
  final List<int>? reminderDays;
  final DateTime createdAt;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  DateTime nextBirthday([DateTime? from]) => BirthdayUtils.nextOccurrence(day, month, from: from);
  int daysUntil([DateTime? from]) => BirthdayUtils.daysUntil(day, month, from: from);
  int? get turningAge => BirthdayUtils.turningAge(day, month, year);
  int? get currentAge => BirthdayUtils.currentAge(day, month, year);
  bool get isToday => daysUntil() == 0;

  Person copyWith({
    String? name,
    int? day,
    int? month,
    int? Function()? year,
    String? relation,
    String? Function()? categoryId,
    String? Function()? photoPath,
    String? Function()? photoUrl,
    String? notes,
    double? Function()? giftBudget,
    List<int>? Function()? reminderDays,
  }) => Person(
    id: id,
    name: name ?? this.name,
    day: day ?? this.day,
    month: month ?? this.month,
    year: year != null ? year() : this.year,
    relation: relation ?? this.relation,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    photoPath: photoPath != null ? photoPath() : this.photoPath,
    photoUrl: photoUrl != null ? photoUrl() : this.photoUrl,
    notes: notes ?? this.notes,
    giftBudget: giftBudget != null ? giftBudget() : this.giftBudget,
    reminderDays: reminderDays != null ? reminderDays() : this.reminderDays,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'birth_day': day,
    'birth_month': month,
    'birth_year': year,
    'relation': relation,
    'category_id': categoryId,
    'photo_path': photoPath,
    'notes': notes,
    'gift_budget': giftBudget,
    'reminder_days': reminderDays,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory Person.fromJson(Map<String, dynamic> j) => Person(
    id: j['id'] as String,
    name: j['name'] as String,
    day: (j['birth_day'] as num).toInt(),
    month: (j['birth_month'] as num).toInt(),
    year: (j['birth_year'] as num?)?.toInt(),
    relation: j['relation'] as String? ?? '',
    categoryId: j['category_id'] as String?,
    photoPath: j['photo_path'] as String?,
    notes: j['notes'] as String? ?? '',
    giftBudget: _double(j['gift_budget']),
    reminderDays: j['reminder_days'] == null ? null : _intList(j['reminder_days']),
    createdAt: _date(j['created_at']),
  );
}

@immutable
class GiftIdea {
  const GiftIdea({
    required this.id,
    required this.personId,
    required this.title,
    this.price,
    this.link = '',
    this.notes = '',
    this.purchased = false,
    required this.createdAt,
  });

  final String id;
  final String personId;
  final String title;
  final double? price;
  final String link;
  final String notes;
  final bool purchased;
  final DateTime createdAt;

  GiftIdea copyWith({String? title, double? Function()? price, String? link, String? notes, bool? purchased}) =>
      GiftIdea(
        id: id,
        personId: personId,
        title: title ?? this.title,
        price: price != null ? price() : this.price,
        link: link ?? this.link,
        notes: notes ?? this.notes,
        purchased: purchased ?? this.purchased,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'person_id': personId,
    'title': title,
    'price': price,
    'link': link,
    'notes': notes,
    'purchased': purchased,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory GiftIdea.fromJson(Map<String, dynamic> j) => GiftIdea(
    id: j['id'] as String,
    personId: j['person_id'] as String,
    title: j['title'] as String,
    price: _double(j['price']),
    link: j['link'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    purchased: j['purchased'] as bool? ?? false,
    createdAt: _date(j['created_at']),
  );
}

@immutable
class BirthdayMessage {
  const BirthdayMessage({
    required this.id,
    required this.personId,
    required this.body,
    this.tone = '',
    required this.updatedAt,
  });

  final String id;
  final String personId;
  final String body;
  final String tone;
  final DateTime updatedAt;

  BirthdayMessage copyWith({String? body, String? tone}) => BirthdayMessage(
    id: id,
    personId: personId,
    body: body ?? this.body,
    tone: tone ?? this.tone,
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'person_id': personId,
    'body': body,
    'tone': tone,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory BirthdayMessage.fromJson(Map<String, dynamic> j) => BirthdayMessage(
    id: j['id'] as String,
    personId: j['person_id'] as String,
    body: j['body'] as String,
    tone: j['tone'] as String? ?? '',
    updatedAt: _date(j['updated_at']),
  );
}

/// Instantâneo imutável de todos os dados do utilizador.
@immutable
class AppData {
  const AppData({
    this.people = const [],
    this.categories = const [],
    this.gifts = const [],
    this.messages = const [],
    this.loaded = false,
  });

  final List<Person> people;
  final List<PersonCategory> categories;
  final List<GiftIdea> gifts;
  final List<BirthdayMessage> messages;
  final bool loaded;

  static const empty = AppData();

  Person? person(String id) => people.where((p) => p.id == id).firstOrNull;
  PersonCategory? category(String? id) => id == null ? null : categories.where((c) => c.id == id).firstOrNull;
  List<GiftIdea> giftsFor(String personId) => gifts.where((g) => g.personId == personId).toList();
  BirthdayMessage? messageFor(String personId) {
    final list = messages.where((m) => m.personId == personId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list.firstOrNull;
  }

  /// Pessoas ordenadas pelo próximo aniversário (hoje primeiro).
  List<Person> get upcoming => [...people]
    ..sort((a, b) {
      final d = a.daysUntil().compareTo(b.daysUntil());
      return d != 0 ? d : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  AppData copyWith({
    List<Person>? people,
    List<PersonCategory>? categories,
    List<GiftIdea>? gifts,
    List<BirthdayMessage>? messages,
    bool? loaded,
  }) => AppData(
    people: people ?? this.people,
    categories: categories ?? this.categories,
    gifts: gifts ?? this.gifts,
    messages: messages ?? this.messages,
    loaded: loaded ?? this.loaded,
  );

  Map<String, dynamic> toExportJson() => {
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'people': people.map((e) => e.toJson()).toList(),
    'categories': categories.map((e) => e.toJson()).toList(),
    'gift_ideas': gifts.map((e) => e.toJson()).toList(),
    'messages': messages.map((e) => e.toJson()).toList(),
  };
}
