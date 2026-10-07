import '../../core/utils/errors.dart';
import '../models/group_models.dart';
import '../models/payment.dart';
import '../repositories/group_repository.dart';
import 'api_client.dart';

/// As regras de acesso (quem vê o grupo, quem pode alterar o quê) estão no
/// servidor — ver backend/src/modules/groups e backend/migrations.
class ApiGroupRepository implements GroupRepository {
  ApiGroupRepository(this._api);

  final ApiClient _api;

  @override
  bool get supportsInvites => true;

  @override
  Future<List<GiftGroup>> fetchGroups() async {
    final rows = (await _api.get('/groups')) as List;
    return [for (final r in rows) GiftGroup.fromJson((r as Map).cast<String, dynamic>())];
  }

  @override
  Future<void> saveGroup(GiftGroup group, {List<GroupMember> newMembers = const []}) =>
      _api.put('/groups/${group.id}', {
        'group': group.toJson(),
        'new_members': [for (final m in newMembers) m.toJson()],
      });

  @override
  Future<void> deleteGroup(String groupId) => _api.delete('/groups/$groupId');

  @override
  Future<void> updateMemberInfo(GroupMember member) => _api.patch('/group-members/${member.id}', {
    'display_name': member.name,
    'custom_amount': member.customAmount,
    'payment_methods': member.payment.toJson(),
  });

  @override
  Future<void> setPaid(GroupMember member, PaymentMethod? method) =>
      _api.post('/group-members/${member.id}/paid', {'method': method?.name});

  @override
  Future<void> setConfirmed(GroupMember member, bool confirmed) =>
      _api.post('/group-members/${member.id}/confirmed', {'confirmed': confirmed});

  @override
  Future<void> removeMember(GroupMember member) => _api.delete('/group-members/${member.id}');

  @override
  Future<void> setPurchased(String groupId, bool purchased) =>
      _api.post('/groups/$groupId/purchased', {'purchased': purchased});

  static String _code(String code) => Uri.encodeComponent(code.trim().toUpperCase());

  @override
  Future<String> joinByCode(String code, String displayName) async {
    try {
      final res = await _api.post('/invite-codes/${_code(code)}/join', {'display_name': displayName});
      return (res as Map)['group_id'] as String;
    } on ApiException catch (e) {
      if (e.code == 'invalid_code') throw const AppException('Código inválido. Confirma com quem te convidou.');
      if (e.code == 'group_closed') throw const AppException('Este grupo já fechou: a prenda foi comprada.');
      rethrow;
    }
  }

  @override
  Future<PaymentDetails> fetchPayee(GiftGroup group) async {
    final res = await _api.get('/groups/${group.id}/payee');
    return PaymentDetails.fromJson((res as Map?)?.cast<String, dynamic>());
  }

  @override
  Future<FoundUser?> findUser(String identifier) async {
    final user = ((await _api.post('/users/find', {'identifier': identifier})) as Map)['user'];
    return user == null ? null : FoundUser.fromJson((user as Map).cast<String, dynamic>());
  }

  @override
  Future<InviteResult> inviteUser(String groupId, String userId) async {
    final res = (await _api.post('/groups/$groupId/invitations', {'user_id': userId}) as Map)['result'];
    return switch (res) {
      'invited' => InviteResult.invited,
      'already_invited' => InviteResult.alreadyInvited,
      'already_member' => InviteResult.alreadyMember,
      'group_closed' => InviteResult.groupClosed,
      _ => InviteResult.notFound,
    };
  }

  @override
  Future<void> cancelInvitation(GroupInvitation invitation) => _api.delete('/invitations/${invitation.id}');

  @override
  Future<List<InvitationPreview>> myInvitations() async {
    final res = (await _api.get('/invitations')) as List;
    return [for (final r in res) InvitationPreview.fromJson((r as Map).cast<String, dynamic>())];
  }

  @override
  Future<String?> respondInvitation(String invitationId, {required bool accept}) async {
    try {
      final res = await _api.post('/invitations/$invitationId/respond', {'accept': accept});
      return (res as Map)['group_id'] as String?;
    } on ApiException catch (e) {
      if (e.code == 'group_closed') throw const AppException('Este grupo já fechou: a prenda foi comprada.');
      if (e.code == 'invitation_not_found') throw const AppException('Este convite já não está disponível.');
      rethrow;
    }
  }

  @override
  Future<GroupPreview> previewByCode(String code) async {
    try {
      return GroupPreview.fromJson(((await _api.get('/invite-codes/${_code(code)}')) as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      if (e.code == 'invalid_code') {
        throw const AppException('Este link de convite não é válido ou o grupo foi eliminado.');
      }
      rethrow;
    }
  }
}
