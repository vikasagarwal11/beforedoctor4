// lib/services/gateway/mock_gateway_client.dart
import 'dart:async';
import 'gateway_client.dart';
import 'gateway_protocol.dart';

class MockGatewayClient implements IGatewayClient {
  final _events = StreamController<GatewayEvent>.broadcast();
  @override
  Stream<GatewayEvent> get events => _events.stream;

  @override
  bool get isConnected => _connected;
  bool _connected = false;

  Timer? _t1;
  Timer? _t2;
  Timer? _t3;

  @override
  Future<void> connect({
    required String firebaseIdToken,
    required Map<String, dynamic> sessionConfig,
  }) async {
    if (_connected) return;
    _connected = true;

    _events.add(const GatewayEvent(
      type: GatewayEventType.sessionState,
      payload: {'state': 'connected'},
    ));

    // Transcript partial simulation
    _t1 = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      final partial = [
        "My son has fever since 2am...",
        "My son has fever since 2am. I gave him Advil...",
        "My son has fever since 2am. I gave him Advil and now he has stomach pain.",
      ];
      final idx = timer.tick - 1;
      if (idx >= partial.length) {
        timer.cancel();
        _events.add(GatewayEvent(
          type: GatewayEventType.transcriptFinal,
          payload: {'text': partial.last},
        ));
        return;
      }
      _events.add(GatewayEvent(
        type: GatewayEventType.transcriptPartial,
        payload: {'text': partial[idx]},
      ));
    });

    // Draft updates (JSON patch style)
    _t2 = Timer(const Duration(seconds: 3), () {
      _events.add(GatewayEvent(
        type: GatewayEventType.aeDraftUpdate,
        payload: {
          'patch': {
            'product_details': {
              'product_name': 'Advil (ibuprofen)',
            },
            'event_details': {
              'symptoms': ['Stomach pain'],
            },
            'patient_info': {
              'age': 6,
              'gender': 'male',
            },
            'reporter_role': 'caregiver',
          }
        },
      ));
    });

    // Another update later
    _t3 = Timer(const Duration(seconds: 6), () {
      _events.add(GatewayEvent(
        type: GatewayEventType.aeDraftUpdate,
        payload: {
          'patch': {
            'event_details': {'onset_date': DateTime(2026, 1, 13, 2, 0).toIso8601String()}
          }
        },
      ));
    });
  }

  @override
  void sendAudioBase64(String base64Pcm16k) {
    // No-op for mock
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    _connected = false;
    _t1?.cancel();
    _t2?.cancel();
    _t3?.cancel();

    _events.add(const GatewayEvent(
      type: GatewayEventType.sessionState,
      payload: {'state': 'disconnected'},
    ));
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }
}

