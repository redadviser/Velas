import '../../data/models/chat_models.dart';

/// "Vista" nas conversas, a partir de até onde cada participante leu.
abstract final class ReadReceipts {
  /// Quem viu [m]: os outros participantes (nem eu, nem quem a enviou) que
  /// já leram até essa mensagem, pela ordem em que a viram.
  static List<Participant> readersOf(ChatMessage m, List<Participant> participants, String me) => [
    for (final p in participants)
      if (p.user.userId != me &&
          p.user.userId != m.senderId &&
          p.lastReadAt != null &&
          !p.lastReadAt!.isBefore(m.createdAt))
        p,
  ]..sort((a, b) => a.lastReadAt!.compareTo(b.lastReadAt!));

  /// Onde mostrar o avatar de cada pessoa: debaixo da mensagem mais recente
  /// que já leu (como no Messenger). [messages] vêm das mais recentes para as
  /// mais antigas. Quem leu até uma mensagem sua não aparece (já se sabe que a viu).
  static Map<String, List<Participant>> positions(
    List<ChatMessage> messages,
    List<Participant> participants,
    String me,
  ) {
    final result = <String, List<Participant>>{};
    for (final p in participants) {
      final readAt = p.lastReadAt;
      if (p.user.userId == me || readAt == null) continue;
      final last = messages.where((m) => m.state == SendState.sent && !m.createdAt.isAfter(readAt)).firstOrNull;
      if (last == null || last.senderId == p.user.userId) continue;
      (result[last.id] ??= []).add(p);
    }
    return result;
  }

  /// Todos os outros já viram [m] (✓✓).
  static bool seenByAll(ChatMessage m, List<Participant> participants, String me) {
    final others = participants.where((p) => p.user.userId != me && p.user.userId != m.senderId).toList();
    return others.isNotEmpty && others.every((p) => p.lastReadAt != null && !p.lastReadAt!.isBefore(m.createdAt));
  }
}
