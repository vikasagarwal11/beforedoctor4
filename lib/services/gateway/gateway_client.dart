// lib/services/gateway/gateway_client.dart
//
// WebSocket gateway client.
// - Connects to your secure gateway (Cloud Run / etc)
// - Emits GatewayEvent stream
// - Sends audio chunks (base64 PCM 16kHz s16le mono)
// - Supports deterministic mock client for UI testing

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'gateway_protocol.dart';

abstract class IGatewayClient {
  Stream<GatewayEvent> get events;
  bool get isConnected;

  Future<void> connect({
    required Uri url,
    required String firebaseIdToken,
    required Map<String, dynamic> sessionConfig,
  });

  Future<void> sendAudioChunkBase64(String base64Pcm16k);
  Future<void> sendAudioChunkBinary(Uint8List pcm16k); // Binary WebSocket frames
  Future<void> sendTurnComplete();
  Future<void> sendBargeIn(); // Cancel server-side audio generation
  Future<void> sendStop();
  Future<void> close();
}

class GatewayClient implements IGatewayClient {
  final _controller = StreamController<GatewayEvent>.broadcast();
  WebSocketChannel? _channel;
  bool _connected = false;

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
    await close();

    _channel = WebSocketChannel.connect(url);
    _connected = true;

    // Send hello/auth handshake
    _channel!.sink.add(clientHello(firebaseIdToken: firebaseIdToken, sessionConfig: sessionConfig));

    _channel!.stream.listen(
      (raw) {
        try {
          // Guard: ignore binary frames (for future binary audio support)
          if (raw is! String) {
            // Binary frame received - ignore for now (can add binary audio later)
            return;
          }
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          _controller.add(GatewayEvent.fromJson(decoded));
        } catch (_) {
          _controller.add(GatewayEvent(type: GatewayEventType.error, payload: {'message': 'Malformed gateway message'}, seq: 0));
        }
      },
      onError: (e) {
        _controller.add(GatewayEvent(type: GatewayEventType.error, payload: {'message': e.toString()}, seq: 0));
      },
      onDone: () {
        _connected = false;
      },
      cancelOnError: false,
    );
  }

  @override
  Future<void> sendAudioChunkBase64(String base64Pcm16k) async {
    if (_channel == null) return;
    _channel!.sink.add(clientAudioChunk(base64Pcm16k: base64Pcm16k));
  }

  /// Send audio as binary frame (performance optimization - no base64 overhead)
  /// Use this instead of sendAudioChunkBase64 for lower latency
  Future<void> sendAudioChunkBinary(Uint8List pcm16k) async {
    if (_channel == null) return;
    // Send raw PCM bytes as WebSocket binary frame
    _channel!.sink.add(pcm16k);
  }

  @override
  Future<void> sendTurnComplete() async {
    if (_channel == null) return;
    _channel!.sink.add(clientTurnComplete());
  }

  @override
  Future<void> sendBargeIn() async {
    if (_channel == null) return;
    _channel!.sink.add(clientBargeIn());
  }

  @override
  Future<void> sendStop() async {
    if (_channel == null) return;
    _channel!.sink.add(clientStop());
  }

  @override
  Future<void> close() async {
    _connected = false;
    await _channel?.sink.close();
    _channel = null;
  }
}
