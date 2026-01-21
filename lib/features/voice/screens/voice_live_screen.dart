// lib/features/voice/screens/voice_live_screen.dart
//
// Gemini-Live style screen wired to VoiceSessionController.
//
// This is a DROP-IN screen. You must provide:
// - gatewayUrl (wss://...)
// - firebaseIdToken (from your auth layer; do NOT hardcode in production)
// - a sessionConfig map (system instruction, schema, etc.)
// - choose MockGatewayClient during UI testing, GatewayClient for real gateway

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../services/audio/audio_engine_service.dart';
import '../../../services/audio/native_audio_engine.dart';
import '../../../services/gateway/gateway_client.dart';
import '../../../services/gateway/mock_gateway_client.dart';
import '../../../services/logging/app_logger.dart';
import '../voice_session_controller.dart';

class VoiceLiveScreen extends HookConsumerWidget {
  static final AppLogger _logger = AppLogger.instance;

  final Uri gatewayUrl;
  final String firebaseIdToken;
  final Map<String, dynamic> sessionConfig;

  /// Set true to run without backend (UI test).
  final bool useMockGateway;

  const VoiceLiveScreen({
    super.key,
    required this.gatewayUrl,
    required this.firebaseIdToken,
    required this.sessionConfig,
    this.useMockGateway = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aura = useAnimationController(duration: const Duration(seconds: 3));
    final detailsOpen = useState(false);

    useEffect(() {
      aura.repeat(reverse: true);
      return null;
    }, [aura]);

    final IGatewayClient gateway = useMemoized(
      () => useMockGateway ? MockGatewayClient() : GatewayClient(),
      [useMockGateway],
    );
    final IAudioEngine audio = useMemoized(
      () => useMockGateway ? NoOpAudioEngine() : NativeAudioEngine(),
      [useMockGateway],
    );
    final controller = useMemoized(
      () => VoiceSessionController(gateway: gateway, audio: audio),
      [gateway, audio],
    );

    // Track if we've successfully started a session (not just attempted)
    final sessionStartedRef = useRef(false);
    // Track if effect is currently running to prevent disposal during active session
    final isRunningRef = useRef(false);

    useEffect(() {
      // Wait for Firebase token to be available before starting session
      if (firebaseIdToken.isEmpty) {
        _logger.info('voice.waiting_for_firebase_token', data: {
          'token_length': firebaseIdToken.length,
        });
        return null; // Will retry when token becomes available
      }

      // If we've already started a session, don't start again
      if (sessionStartedRef.value || isRunningRef.value) {
        _logger.debug('voice.session_already_running', data: {
          'session_started': sessionStartedRef.value,
          'is_running': isRunningRef.value,
        });
        return null;
      }

      isRunningRef.value = true;

      Future.microtask(() async {
        // Permission warm-up: request mic permission at UI level before starting session
        // This improves UX and prevents WebSocket timeouts
        // Note: Request permission even in mock mode since audio engine still needs it
        
        // Check current permission status first
        final status = await Permission.microphone.status;
        _logger.info('voice.permission.status', data: {
          'permission': 'microphone',
          'status': status.toString(),
        });
        
        bool micGranted = false;
        PermissionStatus finalStatus = status; // Track final status for logging
        
        if (status.isGranted) {
          micGranted = true;
          finalStatus = status;
          _logger.info('voice.permission.already_granted');
        } else if (status.isDenied) {
          // Permission not yet requested or was denied - request it
          _logger.info('voice.permission.requesting');
          final result = await Permission.microphone.request();
          micGranted = result.isGranted;
          finalStatus = result; // Use result status, not initial status
          _logger.info('voice.permission.request_result', data: {
            'granted': micGranted,
            'status': result.toString(),
          });
        } else if (status.isPermanentlyDenied) {
          // Permission was permanently denied - user must enable in Settings
          // DO NOT auto-open Settings - it backgrounds the app and prevents permission prompt
          // User can manually open Settings via button in error UI
          finalStatus = status;
          _logger.warn('voice.permission.permanently_denied', data: {
            'permission': 'microphone',
            'message': 'User must enable microphone in Settings → Privacy & Security → Microphone',
            'note': 'Not auto-opening Settings to allow OS prompt to appear if status changes',
          });
          micGranted = false;
        } else {
          // Unknown status - try requesting anyway
          _logger.warn('voice.permission.unknown_status', data: {'status': status.toString()});
          final result = await Permission.microphone.request();
          micGranted = result.isGranted;
          finalStatus = result; // Use result status
        }
        
        if (!micGranted) {
          _logger.warn('voice.permission.denied_at_ui', data: {
            'permission': 'microphone',
            'final_status': finalStatus.toString(), // Use tracked final status
          });
          // Controller will handle the error state when start() is called
        }

        await controller.start(
          gatewayUrl: gatewayUrl,
          firebaseIdToken: firebaseIdToken,
          sessionConfig: sessionConfig,
        );
        
        // Mark session as started only after successful start
        sessionStartedRef.value = true;
        isRunningRef.value = false;
      }).catchError((error) {
        // Reset flag on error so we can retry if token is refreshed
        sessionStartedRef.value = false;
        isRunningRef.value = false;
        _logger.error('voice.session_start_failed', error: error);
      });
      
      // Cleanup: Only dispose if session hasn't successfully started
      // This prevents premature disposal during active connections when dependencies change
      return () {
        // If session hasn't started yet, safe to dispose
        // If session started, keep it alive (will be disposed on actual widget unmount)
        if (!sessionStartedRef.value && !isRunningRef.value) {
          _logger.debug('voice.disposing_controller_before_session_start');
          unawaited(controller.dispose());
        } else {
          _logger.debug('voice.skipping_dispose_session_active', data: {
            'session_started': sessionStartedRef.value,
            'is_running': isRunningRef.value,
          });
        }
        // Reset running flag on cleanup
        isRunningRef.value = false;
      };
    }, [controller, firebaseIdToken, gatewayUrl, sessionConfig]); // Include all deps but handle disposal carefully

    useListenable(controller);
    useListenable(aura);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildAura(aura, controller),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context, controller, detailsOpen),
                const SizedBox(height: 14),
                Expanded(child: _buildTranscriptArea(controller)),
                _buildDock(context, controller, detailsOpen),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _auraColor(VoiceSessionController controller) {
    if (controller.uiState == VoiceUiState.emergency) return Colors.redAccent;
    return Colors.blueAccent;
  }

  Widget _buildAura(AnimationController aura, VoiceSessionController controller) {
    final base = _auraColor(controller);
    final intensity = 0.25 + (aura.value * 0.35);

    return Positioned(
      bottom: -120,
      left: -80,
      right: -80,
      child: Container(
        height: 520,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              base.withOpacity(intensity),
              base.withOpacity(0.08),
              Colors.transparent,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, VoiceSessionController controller, ValueNotifier<bool> detailsOpen) {
    final label = switch (controller.uiState) {
      VoiceUiState.ready => 'Ready',
      VoiceUiState.connecting => 'Connecting…',
      VoiceUiState.listening => controller.isMicMuted ? 'Muted' : '🎙️ Recording…',
      VoiceUiState.speaking => 'Speaking',
      VoiceUiState.processing => 'Processing…',
      VoiceUiState.emergency => 'Urgent',
      VoiceUiState.stopped => 'Stopped',
      VoiceUiState.error => 'Error',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          // Show recording indicator when actively recording
          if (controller.uiState == VoiceUiState.listening && !controller.isMicMuted)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _RecordingIndicator(),
            ),
          Expanded(
            child: Center(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          IconButton(
            onPressed: () => _toggleDetails(context, detailsOpen, controller),
            icon: const Icon(Icons.tune, color: Colors.white),
            tooltip: 'Details',
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptArea(VoiceSessionController controller) {
    // User transcripts (what the user said)
    final userPartial = controller.userTranscriptPartial.trim();
    final userFinal = controller.userTranscriptFinal.trim();
    
    // Assistant captions (what the assistant is saying)
    final assistantPartial = controller.assistantCaptionPartial.trim();
    final assistantFinal = controller.assistantCaptionFinal.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.uiState == VoiceUiState.emergency && (controller.emergencyBanner?.isNotEmpty ?? false))
            _EmergencyBanner(text: controller.emergencyBanner!, onDismiss: controller.clearEmergency),

          if (controller.uiState == VoiceUiState.error && (controller.lastError?.isNotEmpty ?? false))
            _PermissionErrorBanner(
              error: controller.lastError!,
              onOpenSettings: () async {
                await openAppSettings();
              },
            ),

          const SizedBox(height: 10),

          if (userFinal.isNotEmpty ||
              userPartial.isNotEmpty ||
              assistantFinal.isNotEmpty ||
              assistantPartial.isNotEmpty)
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (userFinal.isNotEmpty)
                      _Bubble(text: userFinal, alignRight: false, isUser: true),
                    if (userPartial.isNotEmpty)
                      _Bubble(text: userPartial, alignRight: false, isUser: true),
                    if (assistantFinal.isNotEmpty)
                      _Bubble(text: assistantFinal, alignRight: true, isUser: false),
                    if (assistantPartial.isNotEmpty)
                      _Bubble(text: assistantPartial, alignRight: true, isUser: false),
                  ],
                ),
              ),
            )
          else if (controller.uiState == VoiceUiState.listening && !controller.isMicMuted)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mic, size: 48, color: Colors.white24),
                    const SizedBox(height: 16),
                    Text(
                      'Listening... Start speaking',
                      style: const TextStyle(color: Colors.white54, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Recording automatically started',
                      style: const TextStyle(color: Colors.white38, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else if (controller.uiState == VoiceUiState.listening && controller.isMicMuted)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mic_off, size: 48, color: Colors.red.withOpacity(0.5)),
                    const SizedBox(height: 16),
                    Text(
                      'Microphone is muted',
                      style: const TextStyle(color: Colors.white54, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the mic button below to unmute',
                      style: const TextStyle(color: Colors.white38, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else if (controller.uiState == VoiceUiState.stopped || controller.uiState == VoiceUiState.error)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      controller.uiState == VoiceUiState.error ? Icons.error_outline : Icons.stop_circle_outlined,
                      size: 48,
                      color: Colors.white24,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      controller.uiState == VoiceUiState.error ? 'Session ended with error' : 'Session ended',
                      style: const TextStyle(color: Colors.white54, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the play button below to start a new session',
                      style: const TextStyle(color: Colors.white38, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            const Spacer(),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildDock(BuildContext context, VoiceSessionController controller, ValueNotifier<bool> detailsOpen) {
    final isStopped = controller.uiState == VoiceUiState.stopped || controller.uiState == VoiceUiState.error;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 26, left: 14, right: 14, top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _DockButton(
            icon: Icons.description_outlined,
            onPressed: () => _toggleDetails(context, detailsOpen, controller),
            tooltip: 'View details',
          ),
          if (!isStopped) ...[
            _DockButton(
              icon: controller.isMicMuted ? Icons.mic_off : Icons.mic,
              color: controller.isMicMuted ? Colors.red : Colors.green,
              onPressed: () async {
                try {
                  await controller.toggleMic();
                } catch (e) {
                  _logger.error('voice.mic_toggle_failed', error: e);
                }
              },
              tooltip: controller.isMicMuted ? 'Tap to unmute' : 'Tap to mute',
            ),
            _DockButton(
              icon: Icons.stop_circle_outlined,
              wide: true,
              color: Colors.redAccent,
              onPressed: () async {
                try {
                  _logger.info('voice.stop_button_pressed');
                  await controller.stop();
                  _logger.info('voice.stop_completed');
                  // VoiceLiveScreen is embedded as a tab in AppShell, not a pushed route
                  // So we just stop the session - user can switch tabs manually
                  // No navigation needed
                } catch (e) {
                  _logger.error('voice.stop_failed', error: e);
                }
              },
              tooltip: 'End session',
            ),
          ] else
            _DockButton(
              icon: Icons.play_circle_outlined,
              wide: true,
              color: Colors.green,
              onPressed: () async {
                try {
                  _logger.info('voice.restart_button_pressed');
                  await controller.start(
                    gatewayUrl: gatewayUrl,
                    firebaseIdToken: firebaseIdToken,
                    sessionConfig: sessionConfig,
                  );
                  _logger.info('voice.restart_completed');
                } catch (e) {
                  _logger.error('voice.restart_failed', error: e);
                }
              },
              tooltip: 'Start new session',
            ),
        ],
      ),
    );
  }

  Future<void> _toggleDetails(
    BuildContext context,
    ValueNotifier<bool> detailsOpen,
    VoiceSessionController controller,
  ) async {
    if (detailsOpen.value) return;
    detailsOpen.value = true;

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B0B0B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DetailsSheet(
        controller: controller,
        onAttest: () => _openAttestationSheet(context, controller),
        onSubmit: () => _handleSubmit(context, controller),
      ),
    );

    detailsOpen.value = false;
  }

  Future<void> _openAttestationSheet(BuildContext context, VoiceSessionController controller) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B0B0B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AttestationSheet(controller: controller),
    );
  }

  void _handleSubmit(BuildContext context, VoiceSessionController controller) {
    if (!controller.canSubmit) return;
    _logger.info('voice.report_submit_tapped', data: {'is_ready': controller.canSubmit});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Submission pipeline is not wired yet.')),
    );
  }
}

class _DockButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool wide;
  final Color color;
  final String? tooltip;

  const _DockButton({
    required this.icon,
    this.onPressed,
    this.wide = false,
    this.color = const Color(0xFF333639),
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: wide ? 92 : 66,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          padding: EdgeInsets.zero,
        ),
        onPressed: onPressed,
        child: Icon(icon, color: Colors.white),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        child: button,
      );
    }
    return button;
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool alignRight;
  final bool isUser; // true for user speech, false for assistant

  const _Bubble({required this.text, required this.alignRight, this.isUser = false});

  @override
  Widget build(BuildContext context) {
    // Different colors for user vs assistant
    final bg = isUser ? const Color(0xFF1E3A5F) : const Color(0xFF202124);
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35)),
      ),
    );
  }
}

class _EmergencyBanner extends StatelessWidget {
  final String text;
  final VoidCallback onDismiss;

  const _EmergencyBanner({required this.text, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.18),
        border: Border.all(color: Colors.redAccent.withOpacity(0.55)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.25))),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _PermissionErrorBanner extends StatelessWidget {
  final String error;
  final VoidCallback onOpenSettings;

  const _PermissionErrorBanner({required this.error, required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final isPermissionError = error.toLowerCase().contains('microphone') || 
                              error.toLowerCase().contains('permission');
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withOpacity(0.15),
        border: Border.all(color: Colors.orangeAccent.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mic_off, color: Colors.orangeAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isPermissionError 
                    ? 'Microphone permission required'
                    : 'Error: $error',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (isPermissionError) ...[
            const SizedBox(height: 8),
            const Text(
              'Enable microphone access in Settings → Privacy & Security → Microphone',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings, size: 16),
                label: const Text('Open Settings'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orangeAccent,
                  side: BorderSide(color: Colors.orangeAccent.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailsSheet extends StatelessWidget {
  final VoiceSessionController controller;
  final VoidCallback onAttest;
  final VoidCallback onSubmit;

  const _DetailsSheet({
    required this.controller,
    required this.onAttest,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final report = controller.draft;
    final c = report.criteria;
    final attestationName = report.reporterAttestationName ?? '—';
    final attestationTimestamp = report.finalAttestationTimestampIso ?? '—';
    final hasAttestation = controller.hasAttestation;

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Report Details', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            _CriteriaRow(label: 'Identifiable Patient', ok: c.hasIdentifiablePatient),
            _CriteriaRow(label: 'Identifiable Reporter', ok: c.hasIdentifiableReporter),
            _CriteriaRow(label: 'Suspect Product', ok: c.hasSuspectProduct),
            _CriteriaRow(label: 'Adverse Event', ok: c.hasAdverseEvent),
            const SizedBox(height: 14),
            _KeyValue(label: 'Product', value: _val(report.productDetails['product_name'] ?? report.productDetails['name'])),
            _KeyValue(label: 'Symptoms', value: _symptoms(report.eventDetails['symptoms'])),
            const SizedBox(height: 12),
            const Text('Narrative Preview', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                report.narrative.isEmpty ? '—' : report.narrative,
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.35),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Attestation', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: hasAttestation ? Colors.lightBlueAccent : Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KeyValue(label: 'Name', value: attestationName),
                  _KeyValue(label: 'Timestamp', value: attestationTimestamp),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onAttest,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(hasAttestation ? 'Update Attestation' : 'Review & Attest'),
                  ),
                ),
                if (hasAttestation) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: controller.clearAttestation,
                    child: const Text('Clear', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            _KeyValue(label: 'Draft Valid', value: report.criteria.isValid ? 'Yes' : 'No'),
            const SizedBox(height: 6),
            Text(
              'Submit is available after minimum criteria and attestation.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: controller.canSubmit ? onSubmit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: controller.canSubmit ? Colors.lightBlueAccent : const Color(0xFF2B2B2B),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Submit Report', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  static String _val(dynamic v) => (v == null) ? '—' : v.toString().trim().isEmpty ? '—' : v.toString();

  static String _symptoms(dynamic v) {
    if (v is List) {
      if (v.isEmpty) return '—';
      return v.map((e) => e.toString()).join(', ');
    }
    return _val(v);
  }
}

class _AttestationSheet extends HookWidget {
  final VoiceSessionController controller;

  const _AttestationSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    final nameController = useTextEditingController(text: controller.draft.reporterAttestationName ?? '');
    final confirmed = useState(false);
    useListenable(nameController);

    final name = nameController.text.trim();
    final canAttest = name.isNotEmpty && confirmed.value;

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Review & Attest', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Confirm the report is accurate and complete before submitting.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Full name',
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF141414),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: confirmed.value,
              onChanged: (value) => confirmed.value = value ?? false,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'I confirm this report is truthful and complete.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your digital signature will include your name and the current timestamp.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canAttest
                    ? () {
                        controller.setAttestation(name: name);
                        Navigator.pop(context);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canAttest ? Colors.lightBlueAccent : const Color(0xFF2B2B2B),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Attest & Continue', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CriteriaRow extends StatelessWidget {
  final String label;
  final bool ok;

  const _CriteriaRow({required this.label, required this.ok});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.circle_outlined, color: ok ? Colors.lightBlueAccent : Colors.white24),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14))),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Pulsing red dot to indicate active recording
class _RecordingIndicator extends StatefulWidget {
  const _RecordingIndicator();

  @override
  State<_RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<_RecordingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withOpacity(_animation.value),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(_animation.value * 0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}
