// lib/services/gateway/gateway_protocol.dart
import 'dart:convert';

enum GatewayEventType {
  sessionState,            // server.session.state
  transcriptPartial,       // server.transcript.partial
  transcriptFinal,         // server.transcript.final
  aeDraftUpdate,           // server.ae_draft.update (json patch)
  audioOut,                // server.audio.out (base64 pcm/opus)
  error,                   // server.error
}

class GatewayEvent {
  final GatewayEventType type;
  final Map<String, dynamic> payload;

  const GatewayEvent({required this.type, required this.payload});

  static GatewayEvent fromJson(Map<String, dynamic> json) {
    final t = json['type'] as String? ?? '';
    return GatewayEvent(
      type: _mapType(t),
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  static GatewayEventType _mapType(String t) {
    switch (t) {
      case 'server.session.state':
        return GatewayEventType.sessionState;
      case 'server.transcript.partial':
        return GatewayEventType.transcriptPartial;
      case 'server.transcript.final':
        return GatewayEventType.transcriptFinal;
      case 'server.ae_draft.update':
        return GatewayEventType.aeDraftUpdate;
      case 'server.audio.out':
        return GatewayEventType.audioOut;
      case 'server.error':
      default:
        return GatewayEventType.error;
    }
  }
}

/// Convenience helpers for outbound messages
String clientHello({
  required String firebaseIdToken,
  required Map<String, dynamic> sessionConfig,
}) {
  return jsonEncode({
    'type': 'client.session.start',
    'payload': {
      'idToken': firebaseIdToken,
      'config': sessionConfig,
    }
  });
}

String clientAudioChunk({
  required String base64Pcm16k, // or opus; decide and lock
}) {
  return jsonEncode({
    'type': 'client.audio.chunk',
    'payload': {'data': base64Pcm16k}
  });
}

String clientStop() {
  return jsonEncode({'type': 'client.session.stop', 'payload': {}});
}

