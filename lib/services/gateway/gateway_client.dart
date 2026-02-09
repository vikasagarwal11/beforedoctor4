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

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'gateway_protocol.dart';

abstract class IGatewayClient {
  Stream<GatewayEvent> get events;
  bool get isConnected;

  Future<void> connect({
    required Uri url,
    required String
        firebaseIdToken, // Keep parameter name for backward compatibility
    required Map<String, dynamic> sessionConfig,
    String? conversationId, // Optional conversation ID for persistence
  });

  Future<void> sendAudioChunkBase64(String base64Pcm16k);
  Future<void> sendAudioChunkBinary(
      Uint8List pcm16k); // Binary WebSocket frames
  Future<void> sendTurnComplete({bool transcribeOnly = false});
  Future<void> sendTextTurn(String text, {String? conversationId});
  Future<void> sendBargeIn(); // Cancel server-side audio generation
  Future<void> sendStop();
  Future<void> close();
}

class GatewayClient implements IGatewayClient {
  final _controller = StreamController<GatewayEvent>.broadcast();
  WebSocketChannel? _channel;
  bool _connected = false;
  int _connectionSeq = 0;
  bool _intentionalClose = false;
  Timer? _pingTimer;

  @override
  Stream<GatewayEvent> get events => _controller.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect({
    required Uri url,
    required String
        firebaseIdToken, // Renamed from Firebase to Supabase, but keeping param name
    required Map<String, dynamic> sessionConfig,
    String? conversationId, // Optional conversation ID for persistence
  }) async {
    await close();

    _intentionalClose = false;
    final int conn = ++_connectionSeq;

    // Use I/O channel to get a real connect timeout on mobile.
    _channel = IOWebSocketChannel.connect(
      url,
      connectTimeout: const Duration(seconds: 6),
    );

    // Wait for handshake to complete so callers can rely on connect() completing.
    await _channel!.ready.timeout(const Duration(seconds: 8));
    _connected = true;

    // Start listening before sending hello to avoid missing early events.
    _channel!.stream.listen(
      (raw) {
        if (conn != _connectionSeq) return;
        try {
          // Gateway emits JSON string events; ignore binary frames.
          if (raw is! String) return;
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          _controller.add(GatewayEvent.fromJson(decoded));
        } catch (_) {
          _controller.add(GatewayEvent(
              type: GatewayEventType.error,
              payload: {'message': 'Malformed gateway message'},
              seq: 0));
        }
      },
      onError: (e) {
        if (conn != _connectionSeq) return;
        _controller.add(GatewayEvent(
            type: GatewayEventType.error,
            payload: {'message': e.toString()},
            seq: 0));
      },
      onDone: () {
        if (conn != _connectionSeq) return;
        _connected = false;
        _pingTimer?.cancel();
        _pingTimer = null;

        // Only surface a disconnect if it wasn't a user/system initiated close.
        if (!_intentionalClose) {
          _controller.add(
            const GatewayEvent(
              type: GatewayEventType.error,
              payload: {'message': 'Gateway disconnected'},
              seq: 0,
            ),
          );
        }
      },
      cancelOnError: false,
    );

    // Send hello/auth handshake
    _channel!.sink.add(clientHello(
      firebaseIdToken: firebaseIdToken,
      sessionConfig: sessionConfig,
      conversationId: conversationId,
    ));

    // Keepalive ping to prevent idle disconnects (ngrok/mobile)
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_channel == null || !_connected) return;
      _channel!.sink.add(jsonEncode({'type': 'client.ping', 'payload': {}}));
    });
  }

  @override
  Future<void> sendAudioChunkBase64(String base64Pcm16k) async {
    if (_channel == null || !_connected) {
      throw StateError('Gateway not connected');
    }
    _channel!.sink.add(clientAudioChunk(base64Pcm16k: base64Pcm16k));
  }

  @override
  Future<void> sendAudioChunkBinary(Uint8List pcm16k) async {
    if (_channel == null || !_connected) {
      throw StateError('Gateway not connected');
    }
    // Gateway supports binary PCM frames.
    _channel!.sink.add(pcm16k);
  }

  @override
  Future<void> sendTurnComplete({bool transcribeOnly = false}) async {
    if (_channel == null || !_connected) {
      throw StateError('Gateway not connected');
    }
    _channel!.sink.add(clientTurnComplete(transcribeOnly: transcribeOnly));
  }

  @override
  Future<void> sendTextTurn(String text, {String? conversationId}) async {
    if (_channel == null || !_connected) {
      throw StateError('Gateway not connected');
    }
    _channel!.sink
        .add(clientTextTurn(text: text, conversationId: conversationId));
  }

  @override
  Future<void> sendBargeIn() async {
    if (_channel == null || !_connected) {
      throw StateError('Gateway not connected');
    }
    _channel!.sink.add(clientBargeIn());
  }

  @override
  Future<void> sendStop() async {
    if (_channel == null || !_connected) {
      throw StateError('Gateway not connected');
    }
    _channel!.sink.add(clientStop());
  }

  @override
  Future<void> close() async {
    // Invalidate any in-flight listeners so their onDone/onError won't affect a new connection.
    _intentionalClose = true;
    _connectionSeq++;
    _connected = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _channel?.sink.close();
    _channel = null;
  }
}
