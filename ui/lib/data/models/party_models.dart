import 'package:flutter/foundation.dart';

/// Resposta de um convidado.
enum Rsvp {
  pending('Por responder'),
  yes('Vai'),
  maybe('Talvez'),
  no('Não vai');

  const Rsvp(this.label);
  final String label;

  static Rsvp parse(Object? v) => Rsvp.values.where((r) => r.name == v).firstOrNull ?? Rsvp.pending;
}

@immutable
class PartyGuest {
  const PartyGuest({required this.id, this.userId, required this.name, this.username, this.rsvp = Rsvp.pending});

  final String id;

  /// `null` = convidado sem conta (acrescentado por quem organiza).
  final String? userId;
  final String name;
  final String? username;
  final Rsvp rsvp;

  PartyGuest copyWith({Rsvp? rsvp}) => PartyGuest(id: id, userId: userId, name: name, username: username, rsvp: rsvp ?? this.rsvp);

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'display_name': name,
    'username': username,
    'rsvp': rsvp.name,
  };

  factory PartyGuest.fromJson(Map<String, dynamic> j) => PartyGuest(
    id: j['id'] as String,
    userId: j['user_id'] as String?,
    name: j['display_name'] as String,
    username: j['username'] as String?,
    rsvp: Rsvp.parse(j['rsvp']),
  );
}

@immutable
class PartyTask {
  const PartyTask({required this.id, required this.title, this.assigneeId, this.done = false});

  final String id;
  final String title;
  final String? assigneeId;
  final bool done;

  PartyTask copyWith({String? title, String? Function()? assigneeId, bool? done}) => PartyTask(
    id: id,
    title: title ?? this.title,
    assigneeId: assigneeId != null ? assigneeId() : this.assigneeId,
    done: done ?? this.done,
  );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'assignee_id': assigneeId, 'done': done};

  factory PartyTask.fromJson(Map<String, dynamic> j) => PartyTask(
    id: j['id'] as String,
    title: j['title'] as String,
    assigneeId: j['assignee_id'] as String?,
    done: j['done'] as bool? ?? false,
  );
}

/// Festa surpresa: só a veem quem a organiza e os convidados.
@immutable
class Party {
  const Party({
    required this.id,
    required this.createdBy,
    required this.title,
    required this.celebrantName,
    this.personId,
    this.startsAt,
    this.place = '',
    this.notes = '',
    this.inviteCode = '',
    this.guests = const [],
    this.tasks = const [],
  });

  final String id;
  final String createdBy;
  final String title;
  final String celebrantName;

  /// Pessoa da lista de quem organiza (os convidados recebem `null`).
  final String? personId;
  final DateTime? startsAt;
  final String place;
  final String notes;
  final String inviteCode;
  final List<PartyGuest> guests;
  final List<PartyTask> tasks;

  bool isHost(String? userId) => userId != null && userId == createdBy;
  PartyGuest? guestFor(String? userId) => userId == null ? null : guests.where((g) => g.userId == userId).firstOrNull;
  PartyGuest? guest(String? id) => id == null ? null : guests.where((g) => g.id == id).firstOrNull;
  int count(Rsvp r) => guests.where((g) => g.rsvp == r).length;
  int get doneTasks => tasks.where((t) => t.done).length;

  /// Já passou (mais de um dia depois da hora marcada).
  bool get isPast => startsAt != null && startsAt!.isBefore(DateTime.now().subtract(const Duration(days: 1)));

  Party copyWith({
    String? title,
    String? celebrantName,
    String? Function()? personId,
    DateTime? Function()? startsAt,
    String? place,
    String? notes,
    List<PartyGuest>? guests,
    List<PartyTask>? tasks,
  }) => Party(
    id: id,
    createdBy: createdBy,
    title: title ?? this.title,
    celebrantName: celebrantName ?? this.celebrantName,
    personId: personId != null ? personId() : this.personId,
    startsAt: startsAt != null ? startsAt() : this.startsAt,
    place: place ?? this.place,
    notes: notes ?? this.notes,
    inviteCode: inviteCode,
    guests: guests ?? this.guests,
    tasks: tasks ?? this.tasks,
  );

  /// O que a API recebe ao criar ou editar.
  Map<String, dynamic> toBody() => {
    'title': title,
    'celebrant_name': celebrantName,
    'person_id': personId,
    'starts_at': startsAt?.toUtc().toIso8601String(),
    'place': place,
    'notes': notes,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_by': createdBy,
    ...toBody(),
    'invite_code': inviteCode,
    'guests': guests.map((g) => g.toJson()).toList(),
    'tasks': tasks.map((t) => t.toJson()).toList(),
  };

  factory Party.fromJson(Map<String, dynamic> j) => Party(
    id: j['id'] as String,
    createdBy: j['created_by'] as String,
    title: j['title'] as String,
    celebrantName: j['celebrant_name'] as String,
    personId: j['person_id'] as String?,
    startsAt: j['starts_at'] == null ? null : DateTime.parse(j['starts_at'] as String).toLocal(),
    place: j['place'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    inviteCode: j['invite_code'] as String? ?? '',
    guests: ((j['guests'] as List?) ?? const []).cast<Map>().map((e) => PartyGuest.fromJson(e.cast())).toList(),
    tasks: ((j['tasks'] as List?) ?? const []).cast<Map>().map((e) => PartyTask.fromJson(e.cast())).toList(),
  );
}
