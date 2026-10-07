import '../models/group_models.dart';
import '../models/payment.dart';

/// Prendas em grupo. Na API os grupos são partilhados entre contas
/// (convite por código); no modo local o administrador gere tudo sozinho.
abstract class GroupRepository {
  /// Se outros utilizadores podem entrar no grupo com um código.
  bool get supportsInvites;

  Future<List<GiftGroup>> fetchGroups();

  /// Cria ou atualiza o grupo e os seus membros (só o administrador).
  Future<void> saveGroup(GiftGroup group, {List<GroupMember> newMembers = const []});

  Future<void> deleteGroup(String groupId);

  /// Nome, valor personalizado e dados de pagamento (administrador).
  Future<void> updateMemberInfo(GroupMember member);

  /// "Já paguei" (o próprio ou o administrador). `method == null` anula.
  Future<void> setPaid(GroupMember member, PaymentMethod? method);

  /// "Recebi" (comprador ou administrador).
  Future<void> setConfirmed(GroupMember member, bool confirmed);

  Future<void> removeMember(GroupMember member);

  /// Marca a prenda como comprada (comprador ou administrador).
  Future<void> setPurchased(String groupId, bool purchased);

  /// Entra num grupo a partir do código de convite e devolve o id do grupo.
  Future<String> joinByCode(String code, String displayName);

  /// Dados de pagamento de quem compra a prenda.
  Future<PaymentDetails> fetchPayee(GiftGroup group);

  /// Procura uma conta por email, telemóvel (E.164) ou username já normalizado.
  /// Devolve `null` se não existir.
  Future<FoundUser?> findUser(String identifier);

  /// Envia um convite (só o administrador).
  Future<InviteResult> inviteUser(String groupId, String userId);

  Future<void> cancelInvitation(GroupInvitation invitation);

  /// Convites recebidos e ainda sem resposta.
  Future<List<InvitationPreview>> myInvitations();

  /// Aceita ou recusa. Ao aceitar devolve o id do grupo.
  Future<String?> respondInvitation(String invitationId, {required bool accept});

  /// Grupo associado a um código de convite (para o ecrã do link).
  Future<GroupPreview> previewByCode(String code);
}
