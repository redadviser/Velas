import 'package:flutter/foundation.dart';

import '../../core/utils/birthday_utils.dart';
import 'payment.dart';

enum SplitMode { equal, custom }

enum ContributionStatus {
  /// Ainda não pagou.
  pending,

  /// Disse que pagou; falta o comprador confirmar.
  paid,

  /// O comprador confirmou que recebeu.
  confirmed,
}

DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

@immutable
class GroupMember {
  const GroupMember({
    required this.id,
    required this.groupId,
    required this.name,
    this.userId,
    this.username = '',
    this.customAmount,
    this.paidAt,
    this.paidMethod,
    this.confirmedAt,
    this.payment = PaymentDetails.empty,
    required this.createdAt,
  });

  final String id;
  final String groupId;

  /// `null` para participantes sem conta (acrescentados pelo administrador).
  final String? userId;
  final String name;

  /// Username no momento em que entrou (distingue pessoas com o mesmo nome).
  final String username;

  /// Só usado quando a divisão é personalizada.
  final double? customAmount;
  final DateTime? paidAt;
  final PaymentMethod? paidMethod;
  final DateTime? confirmedAt;

  /// Dados de pagamento introduzidos à mão (participantes sem conta).
  final PaymentDetails payment;
  final DateTime createdAt;

  bool get hasAccount => userId != null;

  ContributionStatus get status => confirmedAt != null
      ? ContributionStatus.confirmed
      : paidAt != null
      ? ContributionStatus.paid
      : ContributionStatus.pending;

  GroupMember copyWith({
    String? name,
    double? Function()? customAmount,
    DateTime? Function()? paidAt,
    PaymentMethod? Function()? paidMethod,
    DateTime? Function()? confirmedAt,
    PaymentDetails? payment,
  }) => GroupMember(
    id: id,
    groupId: groupId,
    userId: userId,
    username: username,
    name: name ?? this.name,
    customAmount: customAmount != null ? customAmount() : this.customAmount,
    paidAt: paidAt != null ? paidAt() : this.paidAt,
    paidMethod: paidMethod != null ? paidMethod() : this.paidMethod,
    confirmedAt: confirmedAt != null ? confirmedAt() : this.confirmedAt,
    payment: payment ?? this.payment,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'group_id': groupId,
    'user_id': userId,
    'display_name': name,
    'username': username.isEmpty ? null : username,
    'custom_amount': customAmount,
    'paid_at': _iso(paidAt),
    'paid_method': paidMethod?.name,
    'confirmed_at': _iso(confirmedAt),
    'payment_methods': payment.toJson(),
    'created_at': _iso(createdAt),
  };

  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
    id: j['id'] as String,
    groupId: j['group_id'] as String,
    userId: j['user_id'] as String?,
    name: j['display_name'] as String? ?? '',
    username: j['username'] as String? ?? '',
    customAmount: (j['custom_amount'] as num?)?.toDouble(),
    paidAt: _dt(j['paid_at']),
    paidMethod: PaymentMethod.tryParse(j['paid_method'] as String?),
    confirmedAt: _dt(j['confirmed_at']),
    payment: PaymentDetails.fromJson((j['payment_methods'] as Map?)?.cast<String, dynamic>()),
    createdAt: _dt(j['created_at']) ?? DateTime.now(),
  );
}

/// Conta encontrada ao procurar por email, telemóvel ou username.
@immutable
class FoundUser {
  const FoundUser({required this.userId, required this.name, required this.username});

  final String userId;
  final String name;
  final String username;

  factory FoundUser.fromJson(Map<String, dynamic> j) => FoundUser(
    userId: j['user_id'] as String,
    name: j['display_name'] as String? ?? '',
    username: j['username'] as String? ?? '',
  );
}

enum InviteResult { invited, alreadyInvited, alreadyMember, groupClosed, notFound }

/// Convite pendente, visto pelos membros do grupo.
@immutable
class GroupInvitation {
  const GroupInvitation({
    required this.id,
    required this.groupId,
    required this.invitedUserId,
    required this.name,
    this.username = '',
    this.status = 'pending',
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String invitedUserId;
  final String name;
  final String username;
  final String status;
  final DateTime createdAt;

  bool get isPending => status == 'pending';

  factory GroupInvitation.fromJson(Map<String, dynamic> j) => GroupInvitation(
    id: j['id'] as String,
    groupId: j['group_id'] as String,
    invitedUserId: j['invited_user_id'] as String,
    name: j['invitee_name'] as String? ?? '',
    username: j['invitee_username'] as String? ?? '',
    status: j['status'] as String? ?? 'pending',
    createdAt: _dt(j['created_at']) ?? DateTime.now(),
  );
}

/// Convite recebido, com o mínimo para decidir se aceitas.
@immutable
class InvitationPreview {
  const InvitationPreview({
    required this.id,
    required this.groupId,
    required this.title,
    required this.celebrantName,
    required this.inviterName,
    required this.memberCount,
  });

  final String id;
  final String groupId;
  final String title;
  final String celebrantName;
  final String inviterName;
  final int memberCount;

  factory InvitationPreview.fromJson(Map<String, dynamic> j) => InvitationPreview(
    id: j['id'] as String,
    groupId: j['group_id'] as String,
    title: j['title'] as String? ?? '',
    celebrantName: j['celebrant_name'] as String? ?? '',
    inviterName: j['inviter_name'] as String? ?? '',
    memberCount: (j['member_count'] as num?)?.toInt() ?? 0,
  );
}

/// O que se vê de um grupo ao abrir um link de convite.
@immutable
class GroupPreview {
  const GroupPreview({
    required this.id,
    required this.title,
    required this.celebrantName,
    required this.adminName,
    required this.memberCount,
    required this.alreadyMember,
    required this.closed,
  });

  final String id;
  final String title;
  final String celebrantName;
  final String adminName;
  final int memberCount;
  final bool alreadyMember;
  final bool closed;

  factory GroupPreview.fromJson(Map<String, dynamic> j) => GroupPreview(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    celebrantName: j['celebrant_name'] as String? ?? '',
    adminName: j['admin_name'] as String? ?? '',
    memberCount: (j['member_count'] as num?)?.toInt() ?? 0,
    alreadyMember: j['already_member'] == true,
    closed: j['closed'] == true,
  );
}

/// Uma prenda comprada a meias por várias pessoas.
@immutable
class GiftGroup {
  const GiftGroup({
    required this.id,
    required this.createdBy,
    required this.title,
    required this.celebrantName,
    this.celebrantDay,
    this.celebrantMonth,
    this.personId,
    this.giftDescription = '',
    this.giftLink = '',
    required this.targetAmount,
    this.splitMode = SplitMode.equal,
    this.buyerMemberId,
    this.deadline,
    this.inviteCode = '',
    this.purchasedAt,
    required this.createdAt,
    this.members = const [],
    this.invitations = const [],
  });

  final String id;

  /// O administrador do grupo.
  final String createdBy;
  final String title;
  final String celebrantName;
  final int? celebrantDay;
  final int? celebrantMonth;

  /// Ligação à pessoa na lista do administrador (só faz sentido para ele).
  final String? personId;
  final String giftDescription;
  final String giftLink;
  final double targetAmount;
  final SplitMode splitMode;

  /// Quem compra a prenda e recebe o dinheiro. Por defeito, o administrador.
  final String? buyerMemberId;
  final DateTime? deadline;
  final String inviteCode;
  final DateTime? purchasedAt;
  final DateTime createdAt;
  final List<GroupMember> members;

  /// Convites ainda sem resposta.
  final List<GroupInvitation> invitations;

  List<GroupMember> get sortedMembers => [...members]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  GroupMember? get admin => members.where((m) => m.userId == createdBy).firstOrNull;

  GroupMember? get buyer =>
      (buyerMemberId == null ? null : members.where((m) => m.id == buyerMemberId).firstOrNull) ?? admin;

  bool isBuyer(GroupMember m) => buyer?.id == m.id;

  GroupMember? memberFor(String? userId) =>
      userId == null ? null : members.where((m) => m.userId == userId).firstOrNull;

  bool isAdminUser(String? userId) => userId != null && userId == createdBy;

  DateTime? get nextBirthday => celebrantDay == null || celebrantMonth == null
      ? null
      : BirthdayUtils.nextOccurrence(celebrantDay!, celebrantMonth!);

  /// Valor que cada membro deve dar. Na divisão igual, os cêntimos que
  /// sobram são distribuídos pelos primeiros membros, para a soma bater certo.
  Map<String, double> get shares {
    final list = sortedMembers;
    if (list.isEmpty) return const {};
    if (splitMode == SplitMode.custom) {
      return {for (final m in list) m.id: m.customAmount ?? 0};
    }
    final cents = (targetAmount * 100).round();
    final base = cents ~/ list.length;
    final rest = cents % list.length;
    return {for (final (i, m) in list.indexed) m.id: (base + (i < rest ? 1 : 0)) / 100};
  }

  double shareOf(GroupMember m) => shares[m.id] ?? 0;

  double get assignedTotal => shares.values.fold(0, (a, b) => a + b);

  /// Diferença entre o valor combinado e a soma das partes (divisão personalizada).
  double get unassigned => ((targetAmount - assignedTotal) * 100).round() / 100;

  /// O comprador não transfere para si próprio: a parte dele conta como paga.
  ContributionStatus statusOf(GroupMember m) => isBuyer(m) ? ContributionStatus.confirmed : m.status;

  double get confirmedAmount => [
    for (final m in members)
      if (statusOf(m) == ContributionStatus.confirmed) shareOf(m),
  ].fold(0, (a, b) => a + b);

  double get reportedAmount => [
    for (final m in members)
      if (statusOf(m) != ContributionStatus.pending) shareOf(m),
  ].fold(0, (a, b) => a + b);

  int get pendingCount => members.where((m) => statusOf(m) == ContributionStatus.pending).length;
  int get awaitingConfirmationCount => members.where((m) => statusOf(m) == ContributionStatus.paid).length;

  bool get fullyCollected => members.isNotEmpty && members.every((m) => statusOf(m) == ContributionStatus.confirmed);

  GiftGroup copyWith({
    String? title,
    String? celebrantName,
    int? Function()? celebrantDay,
    int? Function()? celebrantMonth,
    String? Function()? personId,
    String? giftDescription,
    String? giftLink,
    double? targetAmount,
    SplitMode? splitMode,
    String? Function()? buyerMemberId,
    DateTime? Function()? deadline,
    DateTime? Function()? purchasedAt,
    List<GroupMember>? members,
    List<GroupInvitation>? invitations,
  }) => GiftGroup(
    id: id,
    createdBy: createdBy,
    title: title ?? this.title,
    celebrantName: celebrantName ?? this.celebrantName,
    celebrantDay: celebrantDay != null ? celebrantDay() : this.celebrantDay,
    celebrantMonth: celebrantMonth != null ? celebrantMonth() : this.celebrantMonth,
    personId: personId != null ? personId() : this.personId,
    giftDescription: giftDescription ?? this.giftDescription,
    giftLink: giftLink ?? this.giftLink,
    targetAmount: targetAmount ?? this.targetAmount,
    splitMode: splitMode ?? this.splitMode,
    buyerMemberId: buyerMemberId != null ? buyerMemberId() : this.buyerMemberId,
    deadline: deadline != null ? deadline() : this.deadline,
    inviteCode: inviteCode,
    purchasedAt: purchasedAt != null ? purchasedAt() : this.purchasedAt,
    createdAt: createdAt,
    members: members ?? this.members,
    invitations: invitations ?? this.invitations,
  );

  /// Colunas da tabela `gift_groups` (sem membros).
  Map<String, dynamic> toJson() => {
    'id': id,
    'created_by': createdBy,
    'title': title,
    'celebrant_name': celebrantName,
    'celebrant_day': celebrantDay,
    'celebrant_month': celebrantMonth,
    'person_id': personId,
    'gift_description': giftDescription,
    'gift_link': giftLink,
    'target_amount': targetAmount,
    'split_mode': splitMode.name,
    'buyer_member_id': buyerMemberId,
    'deadline': deadline == null
        ? null
        : '${deadline!.year.toString().padLeft(4, '0')}-${deadline!.month.toString().padLeft(2, '0')}-${deadline!.day.toString().padLeft(2, '0')}',
    'purchased_at': _iso(purchasedAt),
    'created_at': _iso(createdAt),
  };

  factory GiftGroup.fromJson(Map<String, dynamic> j) {
    final deadline = j['deadline'] as String?;
    return GiftGroup(
      id: j['id'] as String,
      createdBy: j['created_by'] as String,
      title: j['title'] as String? ?? '',
      celebrantName: j['celebrant_name'] as String? ?? '',
      celebrantDay: (j['celebrant_day'] as num?)?.toInt(),
      celebrantMonth: (j['celebrant_month'] as num?)?.toInt(),
      personId: j['person_id'] as String?,
      giftDescription: j['gift_description'] as String? ?? '',
      giftLink: j['gift_link'] as String? ?? '',
      targetAmount: (j['target_amount'] as num?)?.toDouble() ?? 0,
      splitMode: j['split_mode'] == 'custom' ? SplitMode.custom : SplitMode.equal,
      buyerMemberId: j['buyer_member_id'] as String?,
      deadline: deadline == null ? null : DateTime.parse(deadline.substring(0, 10)),
      inviteCode: j['invite_code'] as String? ?? '',
      purchasedAt: _dt(j['purchased_at']),
      createdAt: _dt(j['created_at']) ?? DateTime.now(),
      members: [
        for (final m in (j['group_members'] as List?) ?? const [])
          GroupMember.fromJson((m as Map).cast<String, dynamic>()),
      ],
      invitations: [
        for (final i in (j['group_invitations'] as List?) ?? const [])
          GroupInvitation.fromJson((i as Map).cast<String, dynamic>()),
      ].where((i) => i.isPending).toList(),
    );
  }
}
