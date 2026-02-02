// Supabase Persistence Module
// Handles saving chat messages (both user and AI) to Supabase for persistence

import { logger } from './logger.js';

/**
 * Persists messages to Supabase
 * Called by the gateway when messages are finalized
 */
export class SupabaseMessagePersistence {
  constructor(supabaseClient) {
    this.client = supabaseClient;
  }

  /**
   * Save a user message to Supabase
   * @param {string} conversationId - UUID of the conversation
   * @param {string} content - Message text
   * @param {string} messageId - Unique message ID (UUID)
   * @returns {Promise<Object>} Saved message
   */
  async saveUserMessage(conversationId, content, messageId) {
    try {
      if (!conversationId || !content || !messageId) {
        throw new Error('Missing required fields: conversationId, content, messageId');
      }

      const response = await this.client.from('messages').insert({
        id: messageId,
        conversation_id: conversationId,
        role: 'user',
        content: content,
        status: 'sent',
      });

      logger.info('persistence.user_message_saved', {
        messageId,
        conversationId,
        contentLength: content.length,
      });

      return response;
    } catch (error) {
      logger.error('persistence.user_message_failed', {
        error: error.message,
        conversationId,
        messageId,
      });
      throw error;
    }
  }

  /**
   * Save an AI (assistant) response to Supabase
   * Called when Vertex AI generates a complete response
   * @param {string} conversationId - UUID of the conversation
   * @param {string} content - Message text (AI response)
   * @param {string} messageId - Unique message ID (UUID)
   * @returns {Promise<Object>} Saved message
   */
  async saveAssistantMessage(conversationId, content, messageId) {
    try {
      if (!conversationId || !content || !messageId) {
        throw new Error('Missing required fields: conversationId, content, messageId');
      }

      const response = await this.client.from('messages').insert({
        id: messageId,
        conversation_id: conversationId,
        role: 'assistant',
        content: content,
        status: 'sent',
      });

      logger.info('persistence.assistant_message_saved', {
        messageId,
        conversationId,
        contentLength: content.length,
      });

      return response;
    } catch (error) {
      logger.error('persistence.assistant_message_failed', {
        error: error.message,
        conversationId,
        messageId,
      });
      throw error;
    }
  }

  /**
   * Update a message in Supabase (e.g., when user edits transcript)
   * @param {string} messageId - UUID of message to update
   * @param {string} content - New message content
   * @returns {Promise<Object>} Updated message
   */
  async updateMessage(messageId, content) {
    try {
      if (!messageId || !content) {
        throw new Error('Missing required fields: messageId, content');
      }

      const response = await this.client
        .from('messages')
        .update({ content })
        .eq('id', messageId);

      logger.info('persistence.message_updated', {
        messageId,
        contentLength: content.length,
      });

      return response;
    } catch (error) {
      logger.error('persistence.message_update_failed', {
        error: error.message,
        messageId,
      });
      throw error;
    }
  }

  /**
   * Get conversation history from Supabase
   * @param {string} conversationId - UUID of conversation
   * @returns {Promise<Array>} List of messages
   */
  async getConversationHistory(conversationId) {
    try {
      const { data, error } = await this.client
        .from('messages')
        .select('*')
        .eq('conversation_id', conversationId)
        .order('created_at', { ascending: true });

      if (error) {
        throw error;
      }

      logger.info('persistence.history_loaded', {
        conversationId,
        messageCount: data?.length || 0,
      });

      return data || [];
    } catch (error) {
      logger.error('persistence.history_load_failed', {
        error: error.message,
        conversationId,
      });
      throw error;
    }
  }

  /**
   * Create a new conversation
   * @param {string} userId - Supabase user ID
   * @param {string} title - Optional conversation title
   * @returns {Promise<Object>} New conversation
   */
  async createConversation(userId, title = null) {
    try {
      if (!userId) {
        throw new Error('Missing userId');
      }

      const { v4: uuidv4 } = await import('uuid');
      const conversationId = uuidv4();

      const response = await this.client.from('conversations').insert({
        id: conversationId,
        user_id: userId,
        title: title || `Voice Chat ${new Date().toLocaleString()}`,
      });

      logger.info('persistence.conversation_created', {
        conversationId,
        userId,
      });

      return { id: conversationId, user_id: userId, title };
    } catch (error) {
      logger.error('persistence.conversation_create_failed', {
        error: error.message,
        userId,
      });
      throw error;
    }
  }
}

export default SupabaseMessagePersistence;
