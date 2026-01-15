// lib/features/voice/voice_session_controller.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../services/gateway/gateway_client.dart';
import '../../services/gateway/gateway_protocol.dart';
import '../../data/models/adverse_event_report.dart';

enum VoiceUiState { ready, listening, thinking, speaking, review, networkDegraded }

class VoiceSessionController extends ChangeNotifier {
  final IGatewayClient gateway;

  VoiceUiState uiState = VoiceUiState.ready;
  String transcript = '';
  String assistantText = '';
  AdverseEventReport draft;

  StreamSubscription<GatewayEvent>? _sub;

  VoiceSessionController({
    required this.gateway,
    AdverseEventReport? initialDraft,
  }) : draft = (initialDraft ??
            AdverseEventReport(
              id: 'draft',
              createdAt: DateTime.now(),
            )).recomputeCriteria();

  void _setState(VoiceUiState s) {
    uiState = s;
    notifyListeners();
  }

  Future<void> start({
    required String firebaseIdToken,
    required Map<String, dynamic> sessionConfig,
  }) async {
    await gateway.connect(firebaseIdToken: firebaseIdToken, sessionConfig: sessionConfig);
    _sub ??= gateway.events.listen(_onEvent);
    _setState(VoiceUiState.ready);
  }

  void _onEvent(GatewayEvent e) {
    switch (e.type) {
      case GatewayEventType.sessionState:
        final st = (e.payload['state'] as String?) ?? '';
        if (st == 'network_degraded') _setState(VoiceUiState.networkDegraded);
        if (st == 'disconnected') _setState(VoiceUiState.ready);
        break;

      case GatewayEventType.transcriptPartial:
        transcript = (e.payload['text'] as String?) ?? transcript;
        notifyListeners();
        break;

      case GatewayEventType.transcriptFinal:
        transcript = (e.payload['text'] as String?) ?? transcript;
        notifyListeners();
        break;

      case GatewayEventType.aeDraftUpdate:
        final patch = (e.payload['patch'] as Map?)?.cast<String, dynamic>();
        if (patch != null) {
          draft = AdverseEventReport.fromJson(_deepMerge(draft.toJson(), patch))
              .recomputeCriteria();
          notifyListeners();
        }
        break;

      case GatewayEventType.audioOut:
        // Hook up to an audio player later (barge-in logic will live here too)
        _setState(VoiceUiState.speaking);
        notifyListeners();
        break;

      case GatewayEventType.error:
        assistantText = (e.payload['message'] as String?) ?? 'Error';
        notifyListeners();
        break;
    }
  }

  Map<String, dynamic> _deepMerge(Map<String, dynamic> a, Map<String, dynamic> b) {
    final out = Map<String, dynamic>.from(a);
    b.forEach((k, v) {
      if (v is Map && out[k] is Map) {
        out[k] = _deepMerge(
          (out[k] as Map).cast<String, dynamic>(),
          (v as Map).cast<String, dynamic>(),
        );
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  void onMicPressedToggle() {
    if (uiState == VoiceUiState.listening) {
      _setState(VoiceUiState.thinking);
      return;
    }
    _setState(VoiceUiState.listening);
  }

  void onEnd() => _setState(VoiceUiState.review);

  @override
  void dispose() {
    _sub?.cancel();
    gateway.dispose();
    super.dispose();
  }
}
