import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../services/logging/app_logger.dart';

enum GatewayEventType {
  sessionState, // Server session state changed
  audioChunk, // AI audio response chunk
  transcriptPartial, // Partial AI transcript
  transcriptFinal, // Final AI transcript
  userTranscript, // User's transcription (if provided)
  error, // Error event from server
  info, // Info/diagnostic event
}

class GatewayEvent {
  final GatewayEventType type;
  final int sequence;
  final Map<String, dynamic> payload;

  GatewayEvent({
    required this.type,
    required this.sequence,
    required this.payload,
  });
}

abstract class IGatewayClient {
  Future<void> connect({
    required Uri url,
    required String firebaseIdToken,
    required Map<String, dynamic> sessionConfig,
  });

  void sendAudio(Uint8List audioBytes);

  Future<void> sendTurnComplete();

  Future<void> close();

  Stream<GatewayEvent> get events;

  bool get isConnected;
}

class GatewayClient implements IGatewayClient {
  final AppLogger _logger = AppLogger.instance;
  final bool preferBinaryAudio;

  WebSocketChannel? _channel;
  final _eventController = StreamController<GatewayEvent>.broadcast();
  int _messageSequence = 0;

  @override
  Stream<GatewayEvent> get events => _eventController.stream;

  @override
  bool get isConnected => _channel != null;

  GatewayClient({this.preferBinaryAudio = false});

  @override
  Future<void> connect({
    required Uri url,
    required String firebaseIdToken,
    required Map<String, dynamic> sessionConfig,
  }) async {
    try {
      _logger.info('gateway.connecting', data: {
        'url': url.toString(),
        'token_length': firebaseIdToken.length,
      });

      // Open WebSocket
      _channel = WebSocketChannel.connect(url);
      _logger.debug('gateway.websocket_created');

      // Wait for connection to be established
      _logger.debug('gateway.waiting_for_ready');
      await _channel!.ready;
      _logger.debug('gateway.ready_completed');

      _logger.info('gateway.connected', data: {
        'url': url.toString(),
      });

      // Send session initialization
      _logger.debug('gateway.sending_session_config');
      _sendMessage('session.config', {
        'firebase_token': firebaseIdToken,
        'config': sessionConfig,
      });
      _logger.debug('gateway.session_config_sent');

      // Start listening for messages
      _logger.debug('gateway.starting_listener');
      _listenForMessages();
      _logger.debug('gateway.listener_started');
    } catch (e) {
      _logger.error('gateway.connect_failed', error: e);
      _channel = null;
      rethrow;
    }
  }

  void _listenForMessages() {
    try {
      _channel!.stream.listen(
        (message) {
          try {
            _handleMessage(message);
          } catch (e) {
            _logger.error('gateway.message_parse_failed', error: e);
          }
        },
        onError: (e) {
          _logger.error('gateway.stream_error', error: e);
          _eventController.add(GatewayEvent(
            type: GatewayEventType.error,
            sequence: _messageSequence++,
            payload: {'message': 'WebSocket stream error: $e'},
          ));
        },
        onDone: () {
          _logger.info('gateway.stream_closed');
          _channel = null;
          _eventController.add(GatewayEvent(
            type: GatewayEventType.error,
            sequence: _messageSequence++,
            payload: {'message': 'WebSocket disconnected'},
          ));
        },
      );
    } catch (e) {
      _logger.error('gateway.listen_setup_failed', error: e);
    }
  }

  void _handleMessage(dynamic message) {
    if (message is String) {
      try {
        // Try JSON format first (gateway sends: {"type": "...", "seq": N, "payload": {...}})
        final json = jsonDecode(message) as Map<String, dynamic>;
        final typeStr = json['type'] as String?;
        final seq = json['seq'] as int? ?? _messageSequence;
        final payload = json['payload'] as Map<String, dynamic>? ?? {};

        if (typeStr == null) {
          _logger.warn('gateway.json_message_missing_type');
          return;
        }

        final type = _parseEventType(typeStr);
        _messageSequence = seq + 1;

        _logger.debug('gateway.message_received_json', data: {
          'type': typeStr,
          'seq': seq,
        });

        _eventController.add(GatewayEvent(
          type: type,
          sequence: seq,
          payload: payload,
        ));
      } catch (e) {
        // Fallback to pipe-delimited format for backwards compatibility
        try {
          final parts = message.split('|');
          if (parts.length < 3) {
            _logger.warn('gateway.invalid_message_format', data: {
              'message': message.substring(0, min(100, message.length)),
            });
            return;
          }

          final typeStr = parts[0];
          final sequenceStr = parts[1];
          final payloadStr = parts.sublist(2).join('|');

          final type = _parseEventType(typeStr);
          final sequence = int.tryParse(sequenceStr) ?? _messageSequence++;

          _eventController.add(GatewayEvent(
            type: type,
            sequence: sequence,
            payload: _parsePayload(payloadStr),
          ));
        } catch (e2) {
          _logger.error('gateway.message_parse_failed_both_formats', data: {
            'message': message.substring(0, min(100, message.length)),
          });
        }
      }
    } else if (message is List<int>) {
      // Binary audio chunk
      _eventController.add(GatewayEvent(
        type: GatewayEventType.audioChunk,
        sequence: _messageSequence++,
        payload: {'audio': Uint8List.fromList(message)},
      ));
    }
  }

  @override
  void sendAudio(Uint8List audioBytes) {
    if (!isConnected) {
      _logger.warn('gateway.send_audio_not_connected', data: {
        'channel_is_null': _channel == null,
      });
      return;
    }

    try {
      // Send as binary frame
      if (preferBinaryAudio) {
        _channel!.sink.add(audioBytes);
      } else {
        // Or encode as base64 string message
        final base64Audio = _base64Encode(audioBytes);
        _sendMessage('audioFrame', {'data': base64Audio});
      }
    } catch (e) {
      _logger.error('gateway.send_audio_failed', error: e);
    }
  }

  @override
  Future<void> sendTurnComplete() async {
    _sendMessage('turnComplete', {});
  }

  @override
  Future<void> close() async {
    try {
      if (_channel != null) {
        await _channel!.sink.close(1000); // Normal closure code
        _logger.info('gateway.closed');
      }
    } catch (e) {
      _logger.error('gateway.close_failed', error: e);
    } finally {
      _channel = null;
      await _eventController.close();
    }
  }

  void _sendMessage(String type, Map<String, dynamic> payload) {
    if (!isConnected) {
      _logger.warn('gateway.send_message_not_connected', data: {
        'type': type,
      });
      return;
    }

    try {
      final sequence = _messageSequence++;
      final message = '$type|$sequence|${payload.toString()}';
      _channel!.sink.add(message);

      _logger.debug('gateway.message_sent', data: {
        'type': type,
        'sequence': sequence,
      });
    } catch (e) {
      _logger.error('gateway.send_message_failed', error: e);
    }
  }

  GatewayEventType _parseEventType(String typeStr) {
    final lower = typeStr.toLowerCase();
    // Handle both dotted and flat formats
    if (lower.contains('session.state') || lower == 'sessionstate') {
      return GatewayEventType.sessionState;
    } else if (lower.contains('audio.out') || lower == 'audiochunk') {
      return GatewayEventType.audioChunk;
    } else if (lower.contains('user.transcript.partial')) {
      return GatewayEventType.userTranscript;
    } else if (lower.contains('user.transcript.final')) {
      return GatewayEventType.transcriptFinal;
    } else if (lower.contains('transcript.partial')) {
      return GatewayEventType.transcriptPartial;
    } else if (lower.contains('transcript.final')) {
      return GatewayEventType.transcriptFinal;
    } else if (lower.contains('error')) {
      return GatewayEventType.error;
    } else {
      return GatewayEventType.info;
    }
  }

  Map<String, dynamic> _parsePayload(String payloadStr) {
    try {
      // Simple key=value parsing (production would use JSON)
      final result = <String, dynamic>{};
      final pairs = payloadStr.split(',');
      for (final pair in pairs) {
        final kv = pair.split('=');
        if (kv.length == 2) {
          result[kv[0].trim()] = kv[1].trim();
        }
      }
      return result;
    } catch (e) {
      return {'raw': payloadStr};
    }
  }

  String _base64Encode(Uint8List data) {
    // Simple base64 encoding (production would use proper library)
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final result = StringBuffer();
    int i = 0;

    while (i < data.length) {
      final b1 = data[i++];
      final b2 = i < data.length ? data[i++] : 0;
      final b3 = i < data.length ? data[i++] : 0;

      final n = (b1 << 16) | (b2 << 8) | b3;

      result.write(alphabet[(n >> 18) & 63]);
      result.write(alphabet[(n >> 12) & 63]);
      result.write(i - 2 < data.length ? alphabet[(n >> 6) & 63] : '=');
      result.write(i - 1 < data.length ? alphabet[n & 63] : '=');
    }

    return result.toString();
  }
}
