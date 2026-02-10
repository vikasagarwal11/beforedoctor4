import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../../services/logging/app_logger.dart';
import '../audio/wav_builder.dart';
import 'gateway_client.dart';
import 'gateway_protocol.dart';

/// Supabase-backed implementation of [IGatewayClient].
///
/// This keeps the existing voice UI/controller intact while switching the
/// "backend" from a WebSocket gateway to a Supabase Edge Function.
///
/// Expected Edge Function:
/// - name: `voice_turn`
/// - input: { audio_wav_b64?: string, text?: string, session_config?: object, conversation_id?: string }
/// - output: { transcript_text?: string, response_text: string, response_audio_pcm_b64?: string }
class SupabaseGatewayClient implements IGatewayClient {
  final _controller = StreamController<GatewayEvent>.broadcast();
  final SupabaseClient _client;
  final AppLogger _logger = AppLogger.instance;

  bool _connected = false;
  bool _closed = false;
  bool _turnInFlight = false;

  // Buffered PCM16 @ 16kHz mono from mic.
  final BytesBuilder _pcm16k = BytesBuilder(copy: false);

  // Stored from connect()
  Map<String, dynamic> _sessionConfig = const {};
  String? _conversationId;

  int _seq = 0;

  SupabaseGatewayClient({SupabaseClient? client})
      : _client = client ?? supabase;

  @override
  Stream<GatewayEvent> get events => _controller.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect({
    required Uri url,
    required String firebaseIdToken,
    required Map<String, dynamic> sessionConfig,
    String? conversationId,
  }) async {
    // url + token are unused here; Supabase client already holds auth session.
    if (_closed) {
      throw StateError('Client is closed');
    }

    _sessionConfig = sessionConfig;
    _conversationId = conversationId;
    _connected = true;

    _emit(GatewayEvent(
      type: GatewayEventType.gatewayInfo,
      payload: {
        'backend': 'supabase',
        'function': 'voice_turn',
      },
      seq: _nextSeq(),
    ));

    _emit(GatewayEvent(
      type: GatewayEventType.sessionState,
      payload: {'state': 'ready'},
      seq: _nextSeq(),
    ));
  }

  @override
  Future<void> sendAudioChunkBase64(String base64Pcm16k) async {
    _ensureConnected();
    final bytes = base64Decode(base64Pcm16k);
    _pcm16k.add(bytes);
  }

  @override
  Future<void> sendAudioChunkBinary(Uint8List pcm16k) async {
    _ensureConnected();
    _pcm16k.add(pcm16k);
  }

  @override
  Future<void> sendTurnComplete({bool transcribeOnly = false}) async {
    _ensureConnected();

    if (_turnInFlight) {
      _emit(GatewayEvent(
        type: GatewayEventType.error,
        payload: {'message': 'Turn already in-flight'},
        seq: _nextSeq(),
      ));
      return;
    }

    _turnInFlight = true;

    final pcm = _pcm16k.takeBytes();
    if (pcm.isEmpty) {
      _turnInFlight = false;
      _emit(GatewayEvent(
        type: GatewayEventType.error,
        payload: {'message': 'No audio captured'},
        seq: _nextSeq(),
      ));
      return;
    }

    _emit(GatewayEvent(
      type: GatewayEventType.sessionState,
      payload: {'state': 'thinking'},
      seq: _nextSeq(),
    ));

    try {
      final wav = buildPcm16Wav(pcm, sampleRate: 16000, channels: 1);
      _logger.info('gateway.sending_audio_turn_request', data: {
        'pcm_bytes': pcm.length,
        'wav_bytes': wav.length,
      });

      final res = await _client.functions.invoke(
        'voice_turn',
        body: {
          'audio_wav_b64': base64Encode(wav),
          'transcribe_only': true,
          'session_config': _sessionConfig,
          if (_conversationId != null) 'conversation_id': _conversationId,
        },
      );

      _logger.info('gateway.audio_turn_response_received', data: {
        'response_type': res.data.runtimeType.toString(),
        'response_is_map': res.data is Map,
        'response_is_string': res.data is String,
        'response_value': res.data
            .toString()
            .substring(0, math.min(200, res.data.toString().length)),
      });

      Map<String, dynamic> data = {};

      if (res.data is Map) {
        data = (res.data as Map).cast<String, dynamic>();
      } else if (res.data is String) {
        try {
          final parsed = jsonDecode(res.data as String);
          if (parsed is Map) {
            data = (parsed as Map).cast<String, dynamic>();
          }
        } catch (e) {
          _logger.error('gateway.failed_to_parse_response_string', data: {
            'error': e.toString(),
            'response_raw': (res.data as String)
                .substring(0, math.min(200, (res.data as String).length)),
          });
        }
      }

      final transcriptText = (data['transcript_text'] as String?)?.trim() ?? '';
      final responseText = (data['response_text'] as String?)?.trim() ?? '';
      final audioPcmB64 =
          (data['response_audio_pcm_b64'] as String?)?.trim() ?? '';

      _logger.info('gateway.asr_turn_response', data: {
        'transcript_length': transcriptText.length,
        'response_length': responseText.length,
        'has_audio': audioPcmB64.isNotEmpty,
        'transcript_text':
            transcriptText.substring(0, math.min(100, transcriptText.length)),
      });

      if (transcriptText.isNotEmpty) {
        _logger.info('gateway.emitting_user_transcript', data: {
          'text': transcriptText,
        });
        _emit(GatewayEvent(
          type: GatewayEventType.userTranscriptFinal,
          payload: {'text': transcriptText},
          seq: _nextSeq(),
        ));
      }

      if (responseText.isNotEmpty) {
        _emit(GatewayEvent(
          type: GatewayEventType.transcriptFinal,
          payload: {'text': responseText},
          seq: _nextSeq(),
        ));
      }

      if (audioPcmB64.isNotEmpty) {
        if (audioPcmB64.isNotEmpty) {
          // === STREAMING AUDIO: Chunk large audio blobs ===
          // This prevents single-message bottlenecks and enables progressive playback.
          // Each chunk is ~48KB base64 (≈1s of 24kHz audio).
          final audioChunks = _chunkBase64Audio(audioPcmB64);

          _logger.info('gateway.streaming_audio_chunks', data: {
            'total_chunks': audioChunks.length,
            'total_audio_b64_length': audioPcmB64.length,
            'chunk_size_approximate':
                audioChunks.isNotEmpty ? audioChunks[0].length : 0,
          });

          // Send each chunk as a separate audioOut event
          for (final chunk in audioChunks) {
            _emit(GatewayEvent(
              type: GatewayEventType.audioOut,
              payload: {'data': chunk},
              seq: _nextSeq(),
            ));
          }

          // DON'T send audioStop here - let silence timer handle completion
          // This allows all chunks to be enqueued and start playing
          // audioStop will still work if user explicitly stops or on next turn
        }
      } else if (responseText.isNotEmpty) {
        // Text response with no audio - still send audioStop so UI knows response is complete
        _emit(GatewayEvent(
          type: GatewayEventType.audioStop,
          payload: {'reason': 'text_only'},
          seq: _nextSeq(),
        ));
      }

      _emit(GatewayEvent(
        type: GatewayEventType.sessionState,
        payload: {'state': 'ready'},
        seq: _nextSeq(),
      ));
    } catch (e) {
      _logger.error('gateway.voice_turn_failed', data: {
        'error': e.toString(),
        'error_type': e.runtimeType.toString(),
      });
      _emit(GatewayEvent(
        type: GatewayEventType.error,
        payload: {'message': 'Supabase voice_turn failed: $e'},
        seq: _nextSeq(),
      ));
    } finally {
      _turnInFlight = false;
    }
  }

  @override
  Future<void> sendTextTurn(String text, {String? conversationId}) async {
    _ensureConnected();

    if (_turnInFlight) {
      _emit(GatewayEvent(
        type: GatewayEventType.error,
        payload: {'message': 'Turn already in-flight'},
        seq: _nextSeq(),
      ));
      return;
    }

    final cleaned = text.trim();
    if (cleaned.isEmpty) return;

    _turnInFlight = true;

    _emit(GatewayEvent(
      type: GatewayEventType.sessionState,
      payload: {'state': 'thinking'},
      seq: _nextSeq(),
    ));

    try {
      final res = await _client.functions.invoke(
        'voice_turn',
        body: {
          'text': cleaned,
          'session_config': _sessionConfig,
          if (conversationId != null) 'conversation_id': conversationId,
          if (conversationId == null && _conversationId != null)
            'conversation_id': _conversationId,
        },
      );

      _logger.info('gateway.voice_turn_raw_response', data: {
        'response_type': res.data.runtimeType.toString(),
        'is_map': res.data is Map,
        'is_string': res.data is String,
        'response_length': res.data.toString().length,
        'response_preview': res.data
            .toString()
            .substring(0, math.min(200, res.data.toString().length)),
      });

      final data = (res.data is Map)
          ? (res.data as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final responseText = (data['response_text'] as String?)?.trim() ?? '';
      final audioPcmB64 =
          (data['response_audio_pcm_b64'] as String?)?.trim() ?? '';

      _logger.info('gateway.text_turn_response_raw', data: {
        'raw_response_keys': data.keys.toList(),
        'response_text_length': responseText.length,
        'audio_b64_length': audioPcmB64.length,
      });

      if (responseText.isNotEmpty) {
        _emit(GatewayEvent(
          type: GatewayEventType.transcriptFinal,
          payload: {'text': responseText},
          seq: _nextSeq(),
        ));
      }

      if (audioPcmB64.isNotEmpty) {
        // === STREAMING AUDIO: Chunk large audio blobs ===
        final audioChunks = _chunkBase64Audio(audioPcmB64);

        _logger.info('gateway.streaming_audio_chunks_text_turn', data: {
          'total_chunks': audioChunks.length,
          'total_audio_b64_length': audioPcmB64.length,
        });

        // Send each chunk as a separate audioOut event
        for (final chunk in audioChunks) {
          _emit(GatewayEvent(
            type: GatewayEventType.audioOut,
            payload: {'data': chunk},
            seq: _nextSeq(),
          ));
        }

        // DON'T send audioStop - let silence timer handle completion
      } else if (responseText.isNotEmpty) {
        // Text-only response: notify playback lifecycle to exit thinking state
        _emit(GatewayEvent(
          type: GatewayEventType.audioStop,
          payload: {'reason': 'text_only'},
          seq: _nextSeq(),
        ));
      }

      _emit(GatewayEvent(
        type: GatewayEventType.sessionState,
        payload: {'state': 'ready'},
        seq: _nextSeq(),
      ));
    } catch (e) {
      _emit(GatewayEvent(
        type: GatewayEventType.error,
        payload: {'message': 'Supabase voice_turn (text) failed: $e'},
        seq: _nextSeq(),
      ));
    } finally {
      _turnInFlight = false;
    }
  }

  @override
  Future<void> sendBargeIn() async {
    // No streaming generation to cancel in this backend.
    return;
  }

  @override
  Future<void> sendStop() async {
    _ensureConnected();
    _pcm16k.clear();
    _emit(GatewayEvent(
      type: GatewayEventType.sessionState,
      payload: {'state': 'stopped'},
      seq: _nextSeq(),
    ));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _connected = false;
    _pcm16k.clear();
    await _controller.close();
  }

  void _ensureConnected() {
    if (_closed) throw StateError('Client is closed');
    if (!_connected) throw StateError('Supabase backend not connected');
  }

  /// Split base64 audio into chunks for streaming delivery.
  /// Prevents single-message bottlenecks and enables progressive playback.
  ///
  /// @param audioB64 - Full audio as base64 string
  /// @param chunkSizeBytes - Target raw bytes per chunk (≈48KB = 1s @ 24kHz)
  /// @returns List of base64 audio chunks
  List<String> _chunkBase64Audio(String audioB64,
      {int chunkSizeBytes = 48000}) {
    if (audioB64.isEmpty) {
      return [];
    }

    // Decode to raw bytes and re-encode per chunk to keep valid base64.
    // Splitting base64 strings directly can create invalid padding.
    Uint8List bytes;
    try {
      bytes = base64Decode(audioB64);
    } catch (_) {
      return [audioB64];
    }

    final chunks = <String>[];
    for (int i = 0; i < bytes.length; i += chunkSizeBytes) {
      final end = (i + chunkSizeBytes).clamp(0, bytes.length);
      chunks.add(base64Encode(bytes.sublist(i, end)));
    }

    return chunks.isNotEmpty ? chunks : [audioB64];
  }

  void _emit(GatewayEvent ev) {
    if (_closed) return;
    _controller.add(ev);
  }

  int _nextSeq() => ++_seq;
}
