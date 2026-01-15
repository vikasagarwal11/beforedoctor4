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

    // Prevent duplicate session starts due to rebuilds
    final startedRef = useRef(false);

    useEffect(() {
      // Ensure session starts only once per screen mount
      if (startedRef.value) return null;
      startedRef.value = true;

      Future.microtask(() async {
        // Permission warm-up: request mic permission at UI level before starting session
        // This improves UX and prevents WebSocket timeouts
        // Note: Request permission even in mock mode since audio engine still needs it
        final micGranted = await Permission.microphone.request().isGranted;
        if (!micGranted) {
          _logger.warn('voice.permission.denied_at_ui', data: {'permission': 'microphone'});
          // Controller will handle the error state when start() is called
        }

        await controller.start(
          gatewayUrl: gatewayUrl,
          firebaseIdToken: firebaseIdToken,
          sessionConfig: sessionConfig,
        );
      });
      return () {
        unawaited(controller.dispose());
      };
    }, [controller]); // Keep deps tight to prevent re-runs

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
      VoiceUiState.listening => 'Listening',
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
    final partial = controller.transcriptPartial.trim();
    final finalText = controller.transcriptFinal.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.uiState == VoiceUiState.emergency && (controller.emergencyBanner?.isNotEmpty ?? false))
            _EmergencyBanner(text: controller.emergencyBanner!, onDismiss: controller.clearEmergency),

          const SizedBox(height: 10),

          if (finalText.isNotEmpty)
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  finalText,
                  style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.35),
                ),
              ),
            )
          else
            const Spacer(),

          if (partial.isNotEmpty)
            _Bubble(text: partial, alignRight: false),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildDock(BuildContext context, VoiceSessionController controller, ValueNotifier<bool> detailsOpen) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26, left: 14, right: 14, top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _DockButton(
            icon: Icons.description_outlined,
            onPressed: () => _toggleDetails(context, detailsOpen, controller),
          ),
          _DockButton(
            icon: Icons.mic,
            onPressed: () {
              // In V1 we auto-start capture. You can add pause/resume here.
            },
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

  const _DockButton({
    required this.icon,
    this.onPressed,
    this.wide = false,
    this.color = const Color(0xFF333639),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool alignRight;

  const _Bubble({required this.text, required this.alignRight});

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFF202124);
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
