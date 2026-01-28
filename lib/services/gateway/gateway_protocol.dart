// lib/services/gateway/gateway_protocol.dart
//
// Production gateway protocol for BeforeDoctor Voice Live.
//
// Design goals:
// - Type-safe event mapping
// - Monotonic sequence numbers for ordering
// - Patch-based draft updates to avoid UI flicker
// - Explicit barge-in + emergency signals

import 'dart:convert';

enum GatewayEventType {
<<<<<<< HEAD
  gatewayInfo, // server.gateway.info
  kpi, // server.kpi
  sessionState, // server.session.state
  userTranscriptPartial, // server.user.transcript.partial
  userTranscriptFinal, // server.user.transcript.final
  transcriptPartial, // server.transcript.partial
  transcriptFinal, // server.transcript.final
  narrativeUpdate, // server.narrative.update  (string or patch)
  aeDraftUpdate, // server.ae_draft.update   (json patch)
  audioOut, // server.audio.out        (base64 pcm24k s16le)
  audioStop, // server.audio.stop       (barge-in / flush playback)
  emergency, // server.triage.emergency
  error, // server.error
=======
  sessionState,            // server.session.state
  userTranscriptPartial,   // server.user.transcript.partial
  userTranscriptFinal,     // server.user.transcript.final
  transcriptPartial,       // server.transcript.partial
  transcriptFinal,         // server.transcript.final
  narrativeUpdate,         // server.narrative.update  (string or patch)
  aeDraftUpdate,           // server.ae_draft.update   (json patch)
  audioOut,                // server.audio.out        (base64 pcm24k s16le)
  audioStop,               // server.audio.stop       (barge-in / flush playback)
  emergency,               // server.triage.emergency
  error,                   // server.error
  unknown,                 // unrecognized event types (logged but ignored)
>>>>>>> 9355153449b734b1f5ac71afb47356d723984193
}

/// Canonical envelope: { type: string, payload: object, seq?: int }
class GatewayEvent {
  final GatewayEventType type;
  final Map<String, dynamic> payload;
  final int seq;

  const GatewayEvent(
      {required this.type, required this.payload, required this.seq});

  static GatewayEvent fromJson(Map<String, dynamic> json) {
    final t = json['type'] as String? ?? '';
    final seq = (json['seq'] is num) ? (json['seq'] as num).toInt() : 0;
    final eventType = _mapType(t);

    // Store original type string in payload for debugging unknown events
    final payload = (json['payload'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    if (eventType == GatewayEventType.unknown || eventType == GatewayEventType.error) {
      payload['_original_type'] = t;
    }

    return GatewayEvent(
<<<<<<< HEAD
      type: _mapType(t),
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
=======
      type: eventType,
      payload: payload,
>>>>>>> 9355153449b734b1f5ac71afb47356d723984193
      seq: seq,
    );
  }

  static GatewayEventType _mapType(String t) {
    switch (t) {
      case 'server.gateway.info':
        return GatewayEventType.gatewayInfo;
      case 'server.kpi':
        return GatewayEventType.kpi;
      case 'server.session.state':
        return GatewayEventType.sessionState;
      case 'server.user.transcript.partial':
        return GatewayEventType.userTranscriptPartial;
      case 'server.user.transcript.final':
        return GatewayEventType.userTranscriptFinal;
      case 'server.transcript.partial':
        return GatewayEventType.transcriptPartial;
      case 'server.transcript.final':
        return GatewayEventType.transcriptFinal;
      case 'server.narrative.update':
        return GatewayEventType.narrativeUpdate;
      case 'server.ae_draft.update':
        return GatewayEventType.aeDraftUpdate;
      case 'server.audio.out':
        return GatewayEventType.audioOut;
      case 'server.audio.stop':
        return GatewayEventType.audioStop;
      case 'server.triage.emergency':
        return GatewayEventType.emergency;
      case 'server.error':
        return GatewayEventType.error;
      default:
        // Unknown event types should be logged but not treated as errors
        return GatewayEventType.unknown;
    }
  }
}

// --------------------- Client → Gateway helpers ---------------------

String clientHello({
  required String firebaseIdToken,
  required Map<String, dynamic> sessionConfig,
}) {
  return jsonEncode({
    'type': 'client.hello',
    'payload': {
      'firebase_id_token': firebaseIdToken,
      'session_config': sessionConfig,
    }
  });
}

/// Audio chunk: base64-encoded PCM 16kHz, s16le, mono.
/// (If you later switch to Opus, lock mimeType and update server.)
String clientAudioChunk({required String base64Pcm16k}) {
  return jsonEncode({
    'type': 'client.audio.chunk',
    'payload': {'data': base64Pcm16k}
  });
}

/// Audio chunk with explicit base64 type (for newer protocol versions).
/// Gateway accepts both client.audio.chunk and client.audio.chunk.base64 for backward compatibility.
String clientAudioChunkBase64({required String base64Pcm16k}) {
  return jsonEncode({
    'type': 'client.audio.chunk.base64',
    'payload': {'data': base64Pcm16k}
  });
}

String clientStop() {
  return jsonEncode({'type': 'client.session.stop', 'payload': {}});
}

/// Signal end of user utterance (turnComplete: true)
String clientTurnComplete() {
  return jsonEncode({'type': 'client.audio.turnComplete', 'payload': {}});
}

/// Signal barge-in: user speaking while AI is responding (interrupt + cancel server audio)
String clientBargeIn() {
  return jsonEncode({
    'type': 'client.audio.bargeIn',
    'payload': {
      'reason': 'user_speaking',
      'timestamp': DateTime.now().toIso8601String(),
    },
  });
}

/// Optional: client ack when it flushed playback (useful for debugging).
String clientAudioFlushed() {
  return jsonEncode({'type': 'client.audio.flushed', 'payload': {}});
}
