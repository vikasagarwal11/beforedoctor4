// Conversation Repository
// Production-grade: Supabase persistence for chat conversations
// Handles all database operations with error handling and caching

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/supabase/supabase_config.dart';
import '../models/conversation.dart';

/// Repository for managing conversations and messages in Supabase
class ConversationRepository {
  final SupabaseClient _client = supabase;
  final _uuid = const Uuid();

  // Cache for active conversation
  Conversation? _activeConversation;
  final List<ChatMessage> _cachedMessages = [];

  /// Ensure there is an authenticated Supabase user (anonymous if needed)
  Future<void> _ensureAuthenticated() async {
    if (_client.auth.currentUser != null) return;

    try {
      await _client.auth.signInAnonymously();
    } catch (_) {
      // Ignore sign-in errors here; downstream calls will fail with details.
    }

    if (_client.auth.currentUser != null) return;

    // Wait briefly for auth state changes (in case a different part of the app signs in)
    final completer = Completer<void>();
    late final StreamSubscription<AuthState> sub;
    sub = _client.auth.onAuthStateChange.listen((data) {
      if (data.session?.user != null && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Give up; callers will surface errors.
    } finally {
      await sub.cancel();
    }
  }

  /// Create a new conversation
  Future<Conversation> createConversation({
    String? title,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _ensureAuthenticated();
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final now = DateTime.now();
      final conversation = Conversation(
        id: _uuid.v4(),
        userId: userId,
        title: title,
        createdAt: now,
        updatedAt: now,
        metadata: metadata,
      );

      // Insert into Supabase
      await _client.from('conversations').insert(conversation.toJson());

      _activeConversation = conversation;
      _cachedMessages.clear();

      return conversation;
    } catch (e) {
      throw Exception('Failed to create conversation: $e');
    }
  }

  /// Get or create the active conversation for the current user
  Future<Conversation> getOrCreateActiveConversation({
    String? title,
  }) async {
    // Return cached if available
    if (_activeConversation != null) {
      return _activeConversation!;
    }

    try {
      await _ensureAuthenticated();
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Try to fetch most recent conversation
      final response = await _client
          .from('conversations')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        _activeConversation = Conversation.fromJson(response);
        return _activeConversation!;
      }

      // No conversation exists, create one
      return await createConversation(
        title: title ?? 'Voice Conversation ${DateTime.now().toLocal()}',
      );
    } catch (e) {
      throw Exception('Failed to get or create conversation: $e');
    }
  }

  /// Add a message to the conversation
  Future<ChatMessage> addMessage({
    required String conversationId,
    required MessageRole role,
    required String content,
    MessageStatus status = MessageStatus.sent,
    String? id,
    DateTime? createdAt,
  }) async {
    try {
      await _ensureAuthenticated();
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final now = createdAt ?? DateTime.now();
      final message = ChatMessage(
        id: id ?? _uuid.v4(),
        conversationId: conversationId,
        role: role,
        content: content,
        timestamp: now,
        status: status,
      );

      // Insert into Supabase
      await _client.from('messages').insert(message.toJson());

      // Update conversation timestamp
      await _client
          .from('conversations')
          .update({'updated_at': DateTime.now().toIso8601String()}).eq(
              'id', conversationId);

      // Add to cache
      _cachedMessages.add(message);

      return message;
    } catch (e) {
      throw Exception('Failed to add message: $e');
    }
  }

  /// Update an existing message (e.g., user edits transcript)
  Future<ChatMessage> updateMessage({
    required String messageId,
    required String content,
  }) async {
    try {
      await _ensureAuthenticated();
      if (content.trim().isEmpty) {
        throw Exception('Message content cannot be empty');
      }

      final response = await _client
          .from('messages')
          .update({'content': content})
          .eq('id', messageId)
          .select()
          .single();

      final updated = ChatMessage.fromJson(response);

      // Update cache
      final index = _cachedMessages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _cachedMessages[index] = updated;
      }

      return updated;
    } catch (e) {
      throw Exception('Failed to update message: $e');
    }
  }

  /// Get all messages for a conversation
  Future<List<ChatMessage>> getMessages(String conversationId) async {
    try {
      await _ensureAuthenticated();
      // Return cache if available
      if (_cachedMessages.isNotEmpty &&
          _cachedMessages.first.conversationId == conversationId) {
        print('[REPO] Returning cached messages: ${_cachedMessages.length}');
        return List.unmodifiable(_cachedMessages);
      }

      // Fetch from Supabase
      final response = await _client
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);

      print(
          '[REPO] Raw response type: ${response.runtimeType}, is list: ${response is List}');
      if (response is List) {
        print('[REPO] Response count: ${response.length}');
      }

      final messages =
          (response as List).map((json) => ChatMessage.fromJson(json)).toList();

      print('[REPO] Parsed messages: ${messages.length}');
      // Update cache
      _cachedMessages.clear();
      _cachedMessages.addAll(messages);

      return messages;
    } catch (e) {
      throw Exception('Failed to get messages: $e');
    }
  }

  /// Stream messages in real-time for a conversation
  Stream<List<ChatMessage>> streamMessages(String conversationId) {
    // Ensure auth before creating a stream. If it fails, stream will error on access.
    unawaited(_ensureAuthenticated());
    // Start with cached/existing messages
    final controller = StreamController<List<ChatMessage>>.broadcast();

    Future<void> attachSubscription() async {
      // Subscribe to real-time updates
      final subscription = _client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true)
          .listen((List<Map<String, dynamic>> data) {
            final messages =
                data.map((json) => ChatMessage.fromJson(json)).toList();

            // Update cache
            _cachedMessages.clear();
            _cachedMessages.addAll(messages);

            if (!controller.isClosed) {
              controller.add(messages);
            }
          });

      controller.onCancel = () {
        subscription.cancel();
      };
    }

    // Fetch initial messages
    getMessages(conversationId).then((messages) {
      if (!controller.isClosed) {
        controller.add(messages);
      }
    });

    unawaited(attachSubscription());

    return controller.stream;
  }

  /// Generate conversation summary
  Future<ConversationSummary> generateSummary(String conversationId) async {
    try {
      final messages = await getMessages(conversationId);

      if (messages.isEmpty) {
        return ConversationSummary(
          conversationId: conversationId,
          keyPoints: [],
          fullTranscript: 'No messages in conversation.',
          generatedAt: DateTime.now(),
        );
      }

      // Build full transcript
      final transcript = StringBuffer();
      final keyPoints = <String>[];

      for (final message in messages) {
        final speaker = message.role == MessageRole.user ? 'User' : 'Assistant';
        transcript.writeln('$speaker: ${message.content}');

        // Extract key points (simple heuristic: look for important keywords)
        if (_isKeyPoint(message.content)) {
          keyPoints.add(message.content);
        }
      }

      return ConversationSummary(
        conversationId: conversationId,
        keyPoints: keyPoints,
        fullTranscript: transcript.toString(),
        generatedAt: DateTime.now(),
      );
    } catch (e) {
      throw Exception('Failed to generate summary: $e');
    }
  }

  /// Simple heuristic to identify key points
  bool _isKeyPoint(String content) {
    final keywords = [
      'fever',
      'pain',
      'medication',
      'diagnosis',
      'symptom',
      'treatment',
      'adverse',
      'reaction',
      'allergic',
      'emergency',
    ];

    final lower = content.toLowerCase();
    return keywords.any((keyword) => lower.contains(keyword));
  }

  /// Get recent conversations for a user
  Future<List<Conversation>> getRecentConversations({int limit = 10}) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response = await _client
          .from('conversations')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false)
          .limit(limit);

      return (response as List)
          .map((json) => Conversation.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to get recent conversations: $e');
    }
  }

  /// Delete a conversation and all its messages
  Future<void> deleteConversation(String conversationId) async {
    try {
      // Delete messages first (cascade delete should handle this, but being explicit)
      await _client
          .from('messages')
          .delete()
          .eq('conversation_id', conversationId);

      // Delete conversation
      await _client.from('conversations').delete().eq('id', conversationId);

      // Clear cache if this was the active conversation
      if (_activeConversation?.id == conversationId) {
        _activeConversation = null;
        _cachedMessages.clear();
      }
    } catch (e) {
      throw Exception('Failed to delete conversation: $e');
    }
  }

  /// Clear cached data
  void clearCache() {
    _activeConversation = null;
    _cachedMessages.clear();
  }

  /// Get active conversation (cached)
  Conversation? get activeConversation => _activeConversation;

  /// Get cached messages
  List<ChatMessage> get cachedMessages => List.unmodifiable(_cachedMessages);
}
