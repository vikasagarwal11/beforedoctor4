// Conversation Data Models
// Production-grade: Chat conversation system with Supabase persistence

import 'package:flutter/foundation.dart';

/// Represents a single message in the conversation
@immutable
class ChatMessage {
  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final MessageStatus status;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.timestamp,
    this.status = MessageStatus.sent,
  });

  /// Create from Supabase JSON
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      role: MessageRole.fromString(json['role'] as String),
      content: json['content'] as String,
      timestamp: DateTime.parse(json['created_at'] as String),
      status: MessageStatus.fromString(json['status'] as String? ?? 'sent'),
    );
  }

  /// Convert to Supabase JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'role': role.value,
      'content': content,
      'created_at': timestamp.toIso8601String(),
      'status': status.value,
    };
  }

  /// Create a copy with updated fields
  ChatMessage copyWith({
    String? id,
    String? conversationId,
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    MessageStatus? status,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Message role (user or AI assistant)
enum MessageRole {
  user('user'),
  assistant('assistant'),
  system('system');

  final String value;
  const MessageRole(this.value);

  static MessageRole fromString(String value) {
    return MessageRole.values.firstWhere(
      (e) => e.value == value,
      orElse: () => MessageRole.user,
    );
  }
}

/// Message delivery status
enum MessageStatus {
  sending('sending'),
  sent('sent'),
  error('error');

  final String value;
  const MessageStatus(this.value);

  static MessageStatus fromString(String value) {
    return MessageStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => MessageStatus.sent,
    );
  }
}

/// Represents a conversation session
@immutable
class Conversation {
  final String id;
  final String userId;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? metadata;

  const Conversation({
    required this.id,
    required this.userId,
    this.title,
    required this.createdAt,
    required this.updatedAt,
    this.metadata,
  });

  /// Create from Supabase JSON
  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Convert to Supabase JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'metadata': metadata,
    };
  }

  /// Create a copy with updated fields
  Conversation copyWith({
    String? id,
    String? userId,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) {
    return Conversation(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Conversation summary for display
@immutable
class ConversationSummary {
  final String conversationId;
  final List<String> keyPoints;
  final String fullTranscript;
  final DateTime generatedAt;

  const ConversationSummary({
    required this.conversationId,
    required this.keyPoints,
    required this.fullTranscript,
    required this.generatedAt,
  });

  /// Format as readable text
  String toReadableText() {
    final buffer = StringBuffer();
    buffer.writeln('CONVERSATION SUMMARY');
    buffer.writeln('Generated: ${generatedAt.toLocal()}');
    buffer.writeln('=' * 50);
    buffer.writeln();

    if (keyPoints.isNotEmpty) {
      buffer.writeln('KEY POINTS:');
      for (var i = 0; i < keyPoints.length; i++) {
        buffer.writeln('${i + 1}. ${keyPoints[i]}');
      }
      buffer.writeln();
    }

    buffer.writeln('FULL TRANSCRIPT:');
    buffer.writeln(fullTranscript);

    return buffer.toString();
  }
}
