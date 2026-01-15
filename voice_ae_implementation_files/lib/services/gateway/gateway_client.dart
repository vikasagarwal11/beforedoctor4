// lib/services/gateway/gateway_client.dart
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'gateway_protocol.dart';

abstract class IGatewayClient {
  Stream<GatewayEvent> get events;
  bool get isConnected;

  Future<void> connect({
    required String firebaseIdToken,
    required Map<String, dynamic> sessionConfig,
  });

  void sendAudioBase64(String base64Pcm16k);

  Future<void> disconnect();
  Future<void> dispose();
}

class GatewayClient implements IGatewayClient {
  final Uri url;
  WebSocketChannel? _channel;

  final _events = StreamController<GatewayEvent>.broadcast();
  @override
  Stream<GatewayEvent> get events => _events.stream;

  GatewayClient({required this.url});

  @override
  bool get isConnected => _channel != null;

  @override
  Future<void> connect({
    required String firebaseIdToken,
    required Map<String, dynamic> sessionConfig,
  }) async {
    if (_channel != null) return;

    _channel = WebSocketChannel.connect(url);

    _channel!.stream.listen(
      (data) {
        try {
          final jsonMap = jsonDecode(data as String) as Map<String, dynamic>;
          _events.add(GatewayEvent.fromJson(jsonMap));
        } catch (_) {
          _events.add(const GatewayEvent(
            type: GatewayEventType.error,
            payload: {'message': 'Invalid event'},
          ));
        }
      },
      onError: (e) => _events.add(GatewayEvent(
        type: GatewayEventType.error,
        payload: {'message': e.toString()},
      )),
      onDone: () => _events.add(const GatewayEvent(
        type: GatewayEventType.sessionState,
        payload: {'state': 'disconnected'},
      )),
    );

    _channel!.sink.add(clientHello(
      firebaseIdToken: firebaseIdToken,
      sessionConfig: sessionConfig,
    ));
  }

  @override
  void sendAudioBase64(String base64Pcm16k) {
    if (_channel == null) return;
    _channel!.sink.add(clientAudioChunk(base64Pcm16k: base64Pcm16k));
  }

  @override
  Future<void> disconnect() async {
    if (_channel == null) return;
    _channel!.sink.add(clientStop());
    await _channel!.sink.close();
    _channel = null;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }
}
