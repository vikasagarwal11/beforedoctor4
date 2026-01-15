// lib/services/gateway/mock_gateway_client.dart
//
// Deterministic mock for UI + state-machine verification.
// Emits:
// - session state transitions
// - transcript partial/final
// - draft JSON patches
// - audioStop (barge-in) and emergency example

import 'dart:async';
import 'dart:convert';

import '../../services/logging/app_logger.dart';
import 'gateway_client.dart';
import 'gateway_protocol.dart';

class MockGatewayClient implements IGatewayClient {
  final _controller = StreamController<GatewayEvent>.broadcast();
  final _logger = AppLogger.instance;
  int _seq = 1;
  bool _connected = false;
  Timer? _timer;
  int _mockAudioCounter = 0;

  @override
  Stream<GatewayEvent> get events => _controller.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect({
    required Uri url,
    required String firebaseIdToken,
    required Map<String, dynamic> sessionConfig,
  }) async {
    // url ignored
    _connected = true;
    _logger.info('mock_gateway.connected', data: {
      'url': url.toString(),
      'has_token': firebaseIdToken.isNotEmpty,
    });

    _emit(GatewayEventType.sessionState, {'state': 'ready'});

    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      _emit(GatewayEventType.sessionState, {'state': 'listening'});
      _emit(GatewayEventType.transcriptPartial, {'text': 'I started Advil yesterday and now I feel nausea...'});

      // Patch product name
      _emit(GatewayEventType.aeDraftUpdate, {
        'patch': {
          'product_details': {'product_name': 'Advil', 'dosage_strength': '200mg'},
          'event_details': {'symptoms': ['nausea']},
        }
      });

      // Narrative preview update
      _emit(GatewayEventType.narrativeUpdate, {'text': 'After starting Advil (200mg), the patient reported nausea.'});

      // Simulate barge-in: stop audio (even though mock doesn't send audio)
      _emit(GatewayEventType.audioStop, {'reason': 'interrupted'});

      // Simulate emergency later
      Timer(const Duration(seconds: 3), () {
        _emit(GatewayEventType.emergency, {
          'severity': 'high',
          'banner': 'If you are experiencing chest pain or trouble breathing, seek urgent care immediately.'
        });
      });
    });
  }

  void _emit(GatewayEventType type, Map<String, dynamic> payload) {
    _controller.add(GatewayEvent(type: type, payload: payload, seq: _seq++));
  }

  @override
  Future<void> sendAudioChunkBase64(String base64Pcm16k) async {
    // In mock mode, treat audio as "user spoke" and emit a draft update.
    // (You can expand this to parse keywords.)
    if (!_connected) {
      _logger.warn('mock_gateway.audio_rejected', data: {'reason': 'not_connected'});
      return;
    }
    
    // Log audio received (every 50th chunk to avoid spam)
    _mockAudioCounter++;
    if (_mockAudioCounter % 50 == 0) {
      _logger.info('mock_gateway.audio_chunk_received', data: {
        'base64_length': base64Pcm16k.length,
        'total_chunks': _mockAudioCounter,
      });
    }
    
    _emit(GatewayEventType.transcriptPartial, {'text': '[mock] receiving audio chunk (${base64Pcm16k.length} b64 chars)'});
  }

  @override
  Future<void> sendStop() async {
    if (!_connected) return;
    _emit(GatewayEventType.sessionState, {'state': 'stopped'});
  }

  @override
  Future<void> close() async {
    _connected = false;
    _timer?.cancel();
    _timer = null;
    await _controller.close();
  }
}
