// Helper methods for VoiceSessionControllerV2
// Production-grade: Transcript merging, message updates, real-time streaming

import '../../data/models/conversation.dart';

extension VoiceSessionHelpers on dynamic {
  /// Merge transcripts from short pauses into one message
  /// Example: "My son has" + "a fever" = "My son has a fever"
  String mergeTranscript(String existing, String incoming) {
    final trimmedExisting = existing.trim();
    final trimmedIncoming = incoming.trim();
    if (trimmedExisting.isEmpty) return trimmedIncoming;
    if (trimmedIncoming.isEmpty) return trimmedExisting;

    final needsSpace = !trimmedExisting.endsWith(' ') &&
        !trimmedExisting.endsWith('\n') &&
        !trimmedExisting.endsWith('.') &&
        !trimmedExisting.endsWith('!') &&
        !trimmedExisting.endsWith('?') &&
        !trimmedExisting.endsWith(',');

    return needsSpace
        ? '$trimmedExisting $trimmedIncoming'
        : '$trimmedExisting $trimmedIncoming';
  }

  /// Upsert message in memory (add if new, update if exists)
  void upsertMessageInMemory(
    List<ChatMessage> messages,
    ChatMessage message,
    Function() notifyListeners,
  ) {
    final index = messages.indexWhere((m) => m.id == message.id);
    if (index == -1) {
      messages.add(message);
    } else {
      messages[index] = message;
    }
    notifyListeners();
  }

  /// Format message for editing (strip extra whitespace)
  String formatMessageForEdit(String content) {
    return content.trim();
  }

  /// Validate message content before sending
  bool isValidMessageContent(String content) {
    final trimmed = content.trim();
    return trimmed.isNotEmpty && trimmed.length <= 10000;
  }
}
