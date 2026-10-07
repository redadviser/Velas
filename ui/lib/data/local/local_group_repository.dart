import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/errors.dart';
import '../models/group_models.dart';
import '../models/models.dart';
import '../repositories/group_repository.dart';
import 'local_auth_repository.dart';

/// Grupos no modo local, partilhados entre as contas criadas neste
/// dispositivo. Segue as mesmas regras do servidor (ver migrações SQL), o
/// que permite testar convites sem backend: cria duas contas, convida uma
/// pela outra e aceita o convite com a segunda.
class LocalGroupRepository implements GroupRepository {
  LocalGroupRepository(this._prefs, this._profile);

  final SharedPreferences _prefs;
  final UserProfile Function() _profile;

  static const _groupsKey = 'velas.local.groups';
  static const _invitesKey = 'velas.local.invitations';
  static const _uuid = Uuid();

  String get _me => _profile().id;

  @override
  bool get supportsInvites => true;

  // ---------------------------------------------------------------------------
  // Armazenamento
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> _list(String key) =>
      ((jsonDecode(_prefs.getString(key) ?? '[]') as List).cast<Map>()).map((e) => e.cast<String, dynamic>()).toList();

  List<Map<String, dynamic>> _read() {
    _migrateLegacy();
    return _list(_groupsKey);
  }

  Future<void> _write(List<Map<String, dynamic>> rows) => _prefs.setString(_groupsKey, jsonEncode(rows));
  Future<void> _writeInvites(List<Map<String, dynamic>> rows) => _prefs.setString(_invitesKey, jsonEncode(rows));

  /// Versões anteriores guardavam os grupos por utilizador.
  void _migrateLegacy() {
    final legacyKey = 'velas.local.groups.$_me';
    final legacy = _prefs.getString(legacyKey);
    if (legacy == null) return;
    final rows = _list(_groupsKey);
    for (final r in (jsonDecode(legacy) as List).cast<Map>()) {
      final row = r.cast<String, dynamic>();
      if ((row['invite_code'] as String? ?? '').isEmpty) row['invite_code'] = _newCode();
      if (!rows.any((x) => x['id'] == row['id'])) rows.add(row);
    }
    _prefs.setString(_groupsKey, jsonEncode(rows));
    _prefs.remove(legacyKey);
  }

  static String _newCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Map<String, dynamic> _row(GiftGroup g) => {
    ...g.toJson(),
    'invite_code': g.inviteCode,
    'group_members': g.members.map((m) => m.toJson()).toList(),
  };

  bool _isMember(GiftGroup g) => g.createdBy == _me || g.members.any((m) => m.userId == _me);

  GiftGroup _group(String groupId) {
    final row = _read().where((r) => r['id'] == groupId).firstOrNull;
    if (row == null) throw const AppException('Este grupo já não existe.');
    return GiftGroup.fromJson(row);
  }

  Future<void> _update(String groupId, GiftGroup Function(GiftGroup) change) async {
    final rows = _read();
    final i = rows.indexWhere((r) => r['id'] == groupId);
    if (i == -1) throw const AppException('Este grupo já não existe.');
    rows[i] = _row(change(GiftGroup.fromJson(rows[i])));
    await _write(rows);
  }

  void _requireAdmin(String groupId) {
    if (_group(groupId).createdBy != _me) {
      throw const AppException('Só o administrador do grupo pode fazer isto.');
    }
  }

  UserProfile? _account(String userId) =>
      LocalAuthRepository.deviceProfiles(_prefs).where((p) => p.id == userId).firstOrNull;

  // ---------------------------------------------------------------------------
  // Grupos e membros
  // ---------------------------------------------------------------------------

  @override
  Future<List<GiftGroup>> fetchGroups() async {
    final invites = _list(_invitesKey).map(GroupInvitation.fromJson).where((i) => i.isPending).toList();
    return [
      for (final g in _read().map(GiftGroup.fromJson))
        if (_isMember(g)) g.copyWith(invitations: invites.where((i) => i.groupId == g.id).toList()),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> saveGroup(GiftGroup group, {List<GroupMember> newMembers = const []}) async {
    final rows = _read();
    final i = rows.indexWhere((r) => r['id'] == group.id);
    if (i != -1 && GiftGroup.fromJson(rows[i]).createdBy != _me) {
      throw const AppException('Só o administrador pode editar o grupo.');
    }
    final existing = i == -1 ? null : GiftGroup.fromJson(rows[i]);
    final merged = group.copyWith(members: [...?existing?.members, ...newMembers]);
    final row = _row(merged)..['invite_code'] = existing?.inviteCode ?? _newCode();
    i == -1 ? rows.add(row) : rows[i] = row;
    await _write(rows);
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    _requireAdmin(groupId);
    await _write(_read()..removeWhere((r) => r['id'] == groupId));
    await _writeInvites(_list(_invitesKey)..removeWhere((r) => r['group_id'] == groupId));
  }

  Future<void> _member(GroupMember member, GroupMember Function(GroupMember) change) => _update(
    member.groupId,
    (g) => g.copyWith(members: [for (final m in g.members) m.id == member.id ? change(m) : m]),
  );

  @override
  Future<void> updateMemberInfo(GroupMember member) => _member(
    member,
    (m) => m.copyWith(name: member.name, customAmount: () => member.customAmount, payment: member.payment),
  );

  @override
  Future<void> setPaid(GroupMember member, PaymentMethod? method) => _member(
    member,
    (m) => m.copyWith(
      paidAt: () => method == null ? null : DateTime.now(),
      paidMethod: () => method,
      confirmedAt: method == null ? () => null : null,
    ),
  );

  @override
  Future<void> setConfirmed(GroupMember member, bool confirmed) => _member(
    member,
    (m) => m.copyWith(
      confirmedAt: () => confirmed ? DateTime.now() : null,
      paidAt: confirmed && m.paidAt == null ? () => DateTime.now() : null,
      paidMethod: confirmed && m.paidAt == null ? () => PaymentMethod.cash : null,
    ),
  );

  @override
  Future<void> removeMember(GroupMember member) async {
    final g = _group(member.groupId);
    if (member.userId == g.createdBy) throw const AppException('O administrador não pode sair do grupo.');
    await _update(
      member.groupId,
      (g) => g.copyWith(
        members: g.members.where((m) => m.id != member.id).toList(),
        buyerMemberId: g.buyerMemberId == member.id ? () => null : null,
      ),
    );
  }

  @override
  Future<void> setPurchased(String groupId, bool purchased) =>
      _update(groupId, (g) => g.copyWith(purchasedAt: () => purchased ? DateTime.now() : null));

  Future<String> _addMe(GiftGroup g) async {
    if (g.purchasedAt != null) throw const AppException('Este grupo já fechou: a prenda foi comprada.');
    final me = _profile();
    if (!g.members.any((m) => m.userId == me.id)) {
      await _update(
        g.id,
        (g) => g.copyWith(
          members: [
            ...g.members,
            GroupMember(
              id: _uuid.v4(),
              groupId: g.id,
              userId: me.id,
              name: me.name,
              username: me.username,
              createdAt: DateTime.now(),
            ),
          ],
        ),
      );
    }
    // Um convite pendente para este grupo fica aceite.
    final invites = _list(_invitesKey);
    for (final r in invites) {
      if (r['group_id'] == g.id && r['invited_user_id'] == me.id && r['status'] == 'pending') {
        r['status'] = 'accepted';
      }
    }
    await _writeInvites(invites);
    return g.id;
  }

  GiftGroup _byCode(String code) {
    final c = code.trim().toUpperCase();
    final row = _read().where((r) => r['invite_code'] == c).firstOrNull;
    if (row == null) throw const AppException('Código inválido. Confirma com quem te convidou.');
    return GiftGroup.fromJson(row);
  }

  @override
  Future<String> joinByCode(String code, String displayName) => _addMe(_byCode(code));

  @override
  Future<GroupPreview> previewByCode(String code) async {
    final g = _byCode(code);
    return GroupPreview(
      id: g.id,
      title: g.title,
      celebrantName: g.celebrantName,
      adminName: _account(g.createdBy)?.name ?? '',
      memberCount: g.members.length,
      alreadyMember: _isMember(g),
      closed: g.purchasedAt != null,
    );
  }

  @override
  Future<PaymentDetails> fetchPayee(GiftGroup group) async {
    final buyer = group.buyer;
    if (buyer == null) return PaymentDetails.empty;
    if (buyer.userId == _me) return _profile().payment;
    if (buyer.userId != null) return _account(buyer.userId!)?.payment ?? PaymentDetails.empty;
    return buyer.payment;
  }

  // ---------------------------------------------------------------------------
  // Convites (entre contas deste dispositivo)
  // ---------------------------------------------------------------------------

  @override
  Future<FoundUser?> findUser(String identifier) async {
    final q = identifier.trim().toLowerCase();
    final match = LocalAuthRepository.deviceProfiles(_prefs).where(
      (p) => p.email.toLowerCase() == q || (p.username.isNotEmpty && p.username == q) || (p.phone.isNotEmpty && p.phone == q),
    );
    final p = match.firstOrNull;
    return p == null ? null : FoundUser(userId: p.id, name: p.name, username: p.username);
  }

  @override
  Future<InviteResult> inviteUser(String groupId, String userId) async {
    _requireAdmin(groupId);
    final g = _group(groupId);
    if (g.purchasedAt != null) return InviteResult.groupClosed;
    if (g.members.any((m) => m.userId == userId)) return InviteResult.alreadyMember;
    final account = _account(userId);
    if (account == null) return InviteResult.notFound;

    final invites = _list(_invitesKey);
    final i = invites.indexWhere((r) => r['group_id'] == groupId && r['invited_user_id'] == userId);
    if (i != -1 && invites[i]['status'] == 'pending') return InviteResult.alreadyInvited;
    final row = {
      'id': i == -1 ? _uuid.v4() : invites[i]['id'],
      'group_id': groupId,
      'invited_user_id': userId,
      'invited_by': _me,
      'invitee_name': account.name,
      'invitee_username': account.username,
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    i == -1 ? invites.add(row) : invites[i] = row;
    await _writeInvites(invites);
    return InviteResult.invited;
  }

  @override
  Future<void> cancelInvitation(GroupInvitation invitation) async {
    _requireAdmin(invitation.groupId);
    await _writeInvites(_list(_invitesKey)..removeWhere((r) => r['id'] == invitation.id));
  }

  @override
  Future<List<InvitationPreview>> myInvitations() async {
    final groups = {for (final g in _read().map(GiftGroup.fromJson)) g.id: g};
    return [
      for (final r in _list(_invitesKey))
        if (r['invited_user_id'] == _me && r['status'] == 'pending' && groups[r['group_id']]?.purchasedAt == null)
          if (groups[r['group_id']] case final g?)
            InvitationPreview(
              id: r['id'] as String,
              groupId: g.id,
              title: g.title,
              celebrantName: g.celebrantName,
              inviterName: _account(r['invited_by'] as String)?.name ?? '',
              memberCount: g.members.length,
            ),
    ];
  }

  @override
  Future<String?> respondInvitation(String invitationId, {required bool accept}) async {
    final invites = _list(_invitesKey);
    final i = invites.indexWhere((r) => r['id'] == invitationId && r['invited_user_id'] == _me && r['status'] == 'pending');
    if (i == -1) throw const AppException('Este convite já não está disponível.');
    if (!accept) {
      invites[i]['status'] = 'declined';
      await _writeInvites(invites);
      return null;
    }
    return _addMe(_group(invites[i]['group_id'] as String));
  }
}
