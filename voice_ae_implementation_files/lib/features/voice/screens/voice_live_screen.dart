import 'package:flutter/material.dart';
import '../voice_session_controller.dart';
import '../../data/models/adverse_event_report.dart';
import '../../../services/gateway/mock_gateway_client.dart';

class VoiceLiveScreen extends StatefulWidget {
  final VoiceSessionController? controller;

  const VoiceLiveScreen({super.key, this.controller});

  @override
  State<VoiceLiveScreen> createState() => _VoiceLiveScreenState();
}

class _VoiceLiveScreenState extends State<VoiceLiveScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _glow;
  late VoiceSessionController _controller;
  bool _detailsOpen = false;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _controller = widget.controller ?? VoiceSessionController(
      gateway: MockGatewayClient(),
    );
    _controller.addListener(_onControllerUpdate);
    
    // Start the session with mock token (replace with real Firebase token later)
    _controller.start(
      firebaseIdToken: 'mock_token_for_testing',
      sessionConfig: {
        'patient_ref': 'p_self',
        'reporter_ref': 'r_self',
        'locale': 'en-US',
      },
    );
  }

  @override
  void dispose() {
    _glow.dispose();
    _controller.removeListener(_onControllerUpdate);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  String get _stateLabel {
    switch (_controller.uiState) {
      case VoiceUiState.ready:
        return "Live";
      case VoiceUiState.listening:
        return "Listening";
      case VoiceUiState.thinking:
        return "Thinking";
      case VoiceUiState.speaking:
        return "Speaking";
      case VoiceUiState.review:
        return "Review";
      case VoiceUiState.networkDegraded:
        return "Network degraded";
    }
  }

  String _formatMinimumCriteria() {
    final draft = _controller.draft;
    final parts = <String>[];
    if (draft.patient.initials != null || draft.patient.age != null || draft.patient.gender != null) {
      parts.add('Patient ✓');
    } else {
      parts.add('Patient ✗');
    }
    if (draft.reporterRole != null || draft.reporterContact != null) {
      parts.add('Reporter ✓');
    } else {
      parts.add('Reporter ✗');
    }
    if (draft.product.productName != null && draft.product.productName!.isNotEmpty) {
      parts.add('Product ✓');
    } else {
      parts.add('Product ✗');
    }
    if (draft.event.symptoms.isNotEmpty || (draft.event.narrative != null && draft.event.narrative!.isNotEmpty)) {
      parts.add('Event ✓');
    } else {
      parts.add('Event ✗');
    }
    return parts.join('  ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: Listenable.merge([_glow, _controller]),
        builder: (context, _) {
          return Stack(
            children: [
              // Aura glow
              Positioned(
                bottom: -140,
                left: -120,
                right: -120,
                child: AnimatedBuilder(
                  animation: _glow,
                  builder: (context, _) {
                    final v = _glow.value;
                    return Container(
                      height: 520,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.blue.withOpacity(0.30 + 0.25 * v),
                            Colors.lightBlueAccent.withOpacity(0.10 + 0.10 * v),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              SafeArea(
                child: Column(
                  children: [
                    _topBar(),
                    const Spacer(),
                    _transcriptCenter(),
                    const Spacer(),
                    _dock(),
                    const SizedBox(height: 18),
                  ],
                ),
              ),

              // Details sheet (secondary)
              if (_detailsOpen) _detailsSheet(),
            ],
          );
        },
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(_stateLabel, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
          const Spacer(),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.shield, color: Colors.white70),
            tooltip: "Privacy",
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.settings, color: Colors.white70),
            tooltip: "Settings",
          ),
        ],
      ),
    );
  }

  Widget _transcriptCenter() {
    final transcript = _controller.transcript.isEmpty
        ? '"Tap mic to start reporting..."'
        : '"${_controller.transcript}"';
    final assistant = _controller.assistantText.isEmpty
        ? ''
        : 'Assistant: ${_controller.assistantText}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        children: [
          const Text("Live transcript", style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 14),
          Text(
            transcript,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.35, fontWeight: FontWeight.w500),
          ),
          if (assistant.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              assistant,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dock() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _pillButton(
            icon: Icons.description,
            label: "Details",
            onPressed: () => setState(() => _detailsOpen = true),
          ),
          _pillButton(
            icon: Icons.mic,
            label: "Mic",
            isPrimary: true,
            onPressed: _controller.onMicPressedToggle,
          ),
          _pillButton(
            icon: Icons.stop,
            label: "End",
            isDanger: true,
            onPressed: _controller.onEnd,
          ),
        ],
      ),
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = false,
    bool isDanger = false,
  }) {
    final bg = isDanger
        ? Colors.redAccent
        : (isPrimary ? const Color(0xFF333639) : const Color(0xFF333639));
    final w = isPrimary ? 92.0 : (isDanger ? 92.0 : 72.0);

    return SizedBox(
      width: w,
      height: 52,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onPressed,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailsSheet() {
    final draft = _controller.draft;
    
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 86),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0D10).withOpacity(0.90),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text("Details (draft)", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  onPressed: () => setState(() => _detailsOpen = false),
                  icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                )
              ],
            ),
            const SizedBox(height: 10),
            _miniRow("Minimum criteria", _formatMinimumCriteria()),
            const SizedBox(height: 10),
            _miniRow("Suspect product", draft.product.productName ?? "Missing"),
            _miniRow("Adverse event", draft.event.symptoms.isNotEmpty 
                ? draft.event.symptoms.join(", ")
                : (draft.event.narrative ?? "Missing")),
            _miniRow("Onset", draft.event.onsetDate?.toString() ?? "Missing"),
            _miniRow("Dose / timing", draft.product.dosageStrength ?? "Missing"),
            if (draft.missingRequired.isNotEmpty) ...[
              const SizedBox(height: 10),
              _miniRow("Missing required", draft.missingRequired.join(", "), isWarning: true),
            ],
            const SizedBox(height: 10),
            const Text(
              "Draft updates continuously. Submission requires explicit confirmation.",
              style: TextStyle(color: Colors.white54, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniRow(String k, String v, {bool isWarning = false}) {
    final missing = v.toLowerCase().contains("missing") || isWarning;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(k, style: const TextStyle(color: Colors.white60, fontSize: 12))),
          Flexible(
            child: Text(
              v,
              style: TextStyle(
                color: missing ? Colors.orangeAccent : Colors.white,
                fontSize: 12,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
