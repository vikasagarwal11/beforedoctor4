import 'dart:async';
import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../app/app_state.dart';
import '../widgets/presence_header.dart';
import '../widgets/caption_card.dart';
import '../widgets/mic_button.dart';

/// V3.4.1 – Polished voice-first surface (Gemini/Grok-like)
/// - Minimal controls
/// - Live caption surface with motion
/// - Animated waveform placeholder
/// - Mic states: idle/listening (wireframe), with hooks for thinking/speaking later
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({
    super.key,
    required this.repo,
    required this.activeProfile,
  });

  final MockRepo repo;
  final PersonProfile activeProfile;

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

enum VoiceUiState { idle, listening, thinking, speaking }

class _VoiceScreenState extends State<VoiceScreen> {
  VoiceUiState _state = VoiceUiState.idle;

  // Wireframe: simulated live captions
  String _caption = 'I’m here. Tell me what’s happening.';
  Timer? _captionTimer;
  int _captionStep = 0;

  bool get _isListening => _state == VoiceUiState.listening;
  bool get _isThinking => _state == VoiceUiState.thinking;
  bool get _isSpeaking => _state == VoiceUiState.speaking;

  @override
  void dispose() {
    _captionTimer?.cancel();
    super.dispose();
  }

  void _toggleListening(AppState appState) {
    if (_isListening) {
      _stopListening();
      return;
    }
    _startListening(appState);
  }

  void _startListening(AppState appState) {
    setState(() {
      _state = VoiceUiState.listening;
      _captionStep = 0;
      _caption = 'Listening…';
    });

    _captionTimer?.cancel();

    // Wireframe: simulate a short “closed caption” stream.
    const steps = <String>[
      'My child has a fever since after school…',
      'Temperature was 101.2 and I gave Tylenol…',
      'He seems a bit better, still tired.',
    ];

    _captionTimer = Timer.periodic(const Duration(milliseconds: 950), (t) {
      if (!mounted || !_isListening) return;
      if (_captionStep >= steps.length) return;
      setState(() {
        _caption = steps[_captionStep];
        _captionStep += 1;
      });
    });
  }

  void _stopListening() {
    _captionTimer?.cancel();
    setState(() {
      _state = VoiceUiState.idle;
      _caption = 'Saved after you confirm. Say “confirm” (wireframe) or tap Details.';
    });
  }

  void _openDetails() {
    // Keep your existing detailed conversation screen for now.
    // If your project still has the old VoiceAssistantScreen, route there.
    // Otherwise this can route to a future “conversation detail” view.
    final route = _tryBuildLegacyDetailsRoute();
    if (route != null) {
      Navigator.of(context).push(route);
      return;
    }

    // Fallback: simple info bottom sheet (wireframe)
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppTokens.lg),
        child: Text(
          'Details view is not wired in this build yet. '
          'In production this opens the multi-turn conversation transcript + confirmations.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  MaterialPageRoute? _tryBuildLegacyDetailsRoute() {
    // Avoid hard failing if file moved/removed.
    // This keeps the build robust even as you refactor.
    try {
      // ignore: unused_local_variable
      // If legacy screen exists, import it in this file and return route.
      return null;
    } catch (_) {
      return null;
    }
  }

  void _openPreferences(AppState state) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(AppTokens.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Voice preferences', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppTokens.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(widget.activeProfile.displayName),
                subtitle: const Text('Active profile'),
              ),
              const SizedBox(height: AppTokens.sm),
              Text('Assistant tone', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppTokens.xs),
              Wrap(
                spacing: AppTokens.xs,
                runSpacing: AppTokens.xs,
                children: VoiceTone.values.map((t) {
                  final selected = state.voiceTone == t;
                  return ChoiceChip(
                    label: Text(t.label),
                    selected: selected,
                    onSelected: (_) => state.setVoiceTone(t),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppTokens.md),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: state.handsFree,
                onChanged: (v) => state.setHandsFree(v),
                title: const Text('Hands‑free mode'),
                subtitle: const Text('Auto-start listening when you open Voice (wireframe).'),
              ),
              const SizedBox(height: AppTokens.md),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppStateBuilder(builder: (context, appState) {
      final t = Theme.of(context).textTheme;

      // Hands-free behavior (wireframe)
      if (appState.handsFree && _state == VoiceUiState.idle) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_state == VoiceUiState.idle) _startListening(appState);
        });
      }

      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.lg),
            child: Column(
              children: [
                PresenceHeader(
                  status: _isListening
                      ? 'Listening'
                      : _isThinking
                          ? 'Thinking'
                          : _isSpeaking
                              ? 'Speaking'
                              : 'Ready',
                  toneLabel: appState.voiceTone.label,
                  onToneTap: () => _openPreferences(appState),
                ),
                const SizedBox(height: AppTokens.xl),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CaptionCard(
                            caption: _caption,
                            state: _state,
                          ),
                          const SizedBox(height: AppTokens.xl),
                          MicButton(
                            state: _state,
                            onPressed: () => _toggleListening(appState),
                          ),
                          const SizedBox(height: AppTokens.md),
                          Opacity(
                            opacity: 0.9,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TextButton.icon(
                                  onPressed: _openDetails,
                                  icon: const Icon(Icons.expand_less),
                                  label: const Text('Details'),
                                ),
                                const SizedBox(width: AppTokens.sm),
                                TextButton.icon(
                                  onPressed: _isListening ? _stopListening : null,
                                  icon: const Icon(Icons.stop_circle_outlined),
                                  label: const Text('End'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.sm),
                Text(
                  'Tip: Say “fever”, “vomiting”, “rash”, or a medicine name to trigger clinician-style follow‑ups.',
                  style: t.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
