// Example: Context-Aware AI Integration
// Shows how to send full conversation history to AI for context-aware responses

import 'package:flutter/material.dart';

import '../voice_session_controller_v2.dart';

/// Example of sending conversation context to the AI gateway
///
/// This ensures the AI remembers previous parts of the conversation
/// and can provide contextually relevant responses.
class ContextAwareAIExample {
  /// Build session config with conversation context
  ///
  /// Call this when starting a voice session to include conversation history
  static Map<String, dynamic> buildSessionConfig(
    VoiceSessionControllerV2 controller, {
    String? systemInstruction,
  }) {
    // Build base system instruction
    final baseInstruction = systemInstruction ??
        '''You are a helpful clinical intake specialist for adverse event reporting.
Ask follow-up questions until you have all 4 minimum criteria:
1) identifiable patient
2) identifiable reporter
3) suspect product
4) adverse event.

Be empathetic and professional.''';

    // Get conversation context from controller
    final conversationContext = controller.buildConversationContext();

    // Combine base instruction with conversation context
    final fullInstruction = conversationContext.isEmpty
        ? baseInstruction
        : '''$baseInstruction

$conversationContext

Remember the above conversation context when responding to the user.''';

    return {
      'system_instruction': {
        'text': fullInstruction,
      },
      'tool_config': {
        'function_calling_config': {
          'mode': 'AUTO',
        },
      },
      'generation_config': {
        'temperature': 0.7,
        'top_p': 0.95,
        'top_k': 40,
        'max_output_tokens': 2048,
      },
    };
  }

  /// Example usage in voice screen
  static void exampleUsage(VoiceSessionControllerV2 controller) {
    // When starting a new session:
    final sessionConfig = buildSessionConfig(controller);

    // Pass to gateway
    controller.start(
      gatewayUrl: Uri.parse('ws://localhost:8080'),
      firebaseIdToken: 'your-token',
      sessionConfig: sessionConfig, // ← Context included here
    );

    // Now the AI will respond with awareness of:
    // - Previous user questions
    // - Previous AI responses
    // - Conversation flow
  }

  /// Example of context-aware conversation
  static String demonstrateContextAwareness() {
    return '''
WITHOUT CONTEXT:
═══════════════════════════════════════════
User: "My child has fever"
AI: "I understand. What is the temperature?"

User: "I gave azithromycin"  ← No context!
AI: "What symptoms are you treating with azithromycin?"
     ^ AI doesn't remember the fever!


WITH CONTEXT:
═══════════════════════════════════════════
System Instruction includes:
  Previous conversation context:
  User: My child has fever
  Assistant: I understand. What is the temperature?
  User: 102 degrees
  Assistant: That's a moderate fever. Have you given any medication?

User: "I gave azithromycin"
AI: "I see you gave azithromycin for the fever. However, azithromycin 
     is an antibiotic typically used for bacterial infections, not fever 
     alone. Was your child diagnosed with a bacterial infection?"
     ^ AI remembers the fever AND the temperature!
''';
  }

  /// Example: Update context mid-session (future enhancement)
  ///
  /// In the future, you could refresh the AI's context mid-session
  /// by sending a new system instruction with updated history
  static Future<void> updateContextMidSession(
    VoiceSessionControllerV2 controller,
  ) async {
    // Stop current session
    await controller.stop();

    // Rebuild config with updated context
    final newConfig = buildSessionConfig(controller);

    // Restart with new context
    await controller.start(
      gatewayUrl: Uri.parse('ws://localhost:8080'),
      firebaseIdToken: 'your-token',
      sessionConfig: newConfig,
    );
  }

  /// Example: Format conversation for different AI models
  static Map<String, dynamic> formatForGemini(
    VoiceSessionControllerV2 controller,
  ) {
    final messages = controller.messages;

    // Convert to Gemini chat history format
    final history = messages.map((msg) {
      return {
        'role': msg.role.value == 'user' ? 'user' : 'model',
        'parts': [
          {'text': msg.content}
        ],
      };
    }).toList();

    return {
      'history': history,
      'systemInstruction': {
        'parts': [
          {
            'text':
                'You are a helpful clinical intake specialist for adverse event reporting.'
          }
        ],
      },
    };
  }

  /// Example: Format conversation for OpenAI
  static List<Map<String, String>> formatForOpenAI(
    VoiceSessionControllerV2 controller,
  ) {
    final messages = controller.messages;

    // Convert to OpenAI messages format
    return [
      {
        'role': 'system',
        'content':
            'You are a helpful clinical intake specialist for adverse event reporting.',
      },
      ...messages.map((msg) {
        return {
          'role': msg.role.value, // 'user' or 'assistant'
          'content': msg.content,
        };
      }),
    ];
  }

  /// Example: Detect context-dependent questions
  ///
  /// Identify when user is asking about something from earlier in conversation
  static bool isContextDependent(String userMessage) {
    final contextIndicators = [
      'it',
      'that',
      'this',
      'they',
      'them',
      'the medication',
      'the symptom',
      'you mentioned',
      'you said',
      'earlier',
      'before',
    ];

    final lower = userMessage.toLowerCase();
    return contextIndicators.any((indicator) => lower.contains(indicator));
  }

  /// Example: Build intelligent prompt with context
  static String buildIntelligentPrompt(
    VoiceSessionControllerV2 controller,
    String newUserMessage,
  ) {
    final hasContext = controller.messages.isNotEmpty;
    final needsContext = isContextDependent(newUserMessage);

    if (!hasContext || !needsContext) {
      // Simple case: no context needed
      return newUserMessage;
    }

    // Build prompt with relevant context
    final context = controller.buildConversationContext();

    return '''Given this conversation history:
$context

User now says: "$newUserMessage"

Respond with full awareness of the conversation history.''';
  }

  /// Example: Key point extraction for AI instruction
  static String extractKeyPointsForAI(VoiceSessionControllerV2 controller) {
    final messages = controller.messages;

    final keyFacts = <String>[];

    for (final msg in messages) {
      // Extract medical facts
      if (msg.content.toLowerCase().contains('fever')) {
        keyFacts.add('Patient has fever');
      }
      if (msg.content.toLowerCase().contains('azithromycin')) {
        keyFacts.add('Patient received azithromycin');
      }
      // Add more keyword detection...
    }

    if (keyFacts.isEmpty) {
      return '';
    }

    return '''
Key facts from conversation:
${keyFacts.map((f) => '- $f').join('\n')}

Remember these facts when responding.''';
  }
}

/// Example widget showing how to use context-aware AI
class ContextAwareAIDemo extends StatelessWidget {
  final VoiceSessionControllerV2 controller;

  const ContextAwareAIDemo({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Show current context
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Context Awareness',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  controller.messages.isEmpty
                      ? 'No context yet'
                      : '${controller.messages.length} messages in context',
                ),
                const SizedBox(height: 8),
                if (controller.messages.isNotEmpty)
                  Text(
                    controller.buildConversationContext(),
                    style:
                        const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
              ],
            ),
          ),
        ),

        // Start button with context
        ElevatedButton(
          onPressed: () {
            final config = ContextAwareAIExample.buildSessionConfig(controller);
            controller.start(
              gatewayUrl: Uri.parse('ws://localhost:8080'),
              firebaseIdToken: 'token',
              sessionConfig: config,
            );
          },
          child: const Text('Start with Context'),
        ),
      ],
    );
  }
}
