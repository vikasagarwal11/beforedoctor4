// DEPRECATED: replaced by lib/features/voice/screens/voice_screen.dart in V3.4.1
import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../shared/widgets/components.dart';
import '../../../app/app_state.dart';
import 'voice_assistant_screen.dart';

class VoiceHubScreen extends StatefulWidget {
  const VoiceHubScreen({
    super.key,
    required this.repo,
    required this.activeProfile,
  });

  final MockRepo repo;
  final PersonProfile activeProfile;

  @override
  State<VoiceHubScreen> createState() => _VoiceHubScreenState();
}

class _VoiceHubScreenState extends State<VoiceHubScreen> {
  bool _listening = false;
  String _liveCaption = '';
  String _status = 'Ready';

  void _toggle() {
    setState(() {
      _listening = !_listening;
      _status = _listening ? 'Listening…' : 'Ready';
      _liveCaption = _listening ? '…' : '';
    });

    if (_listening) {
      // Wireframe: simulate live caption updates.
      Future.delayed(const Duration(milliseconds: 650), () {
        if (!mounted || !_listening) return;
        setState(() => _liveCaption = 'My child has a fever since after school…');
      });
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (!mounted || !_listening) return;
        setState(() => _liveCaption = 'Temperature was 101.2 and I gave Tylenol…');
      });
    }
  }

  void _openConversation() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceAssistantScreen(
          repo: widget.repo,
          profile: widget.activeProfile,
        ),
      ),
    );
  }

  void _openMoreSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final state = AppState.of(context);
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
                subtitle: const Text('Active profile (wireframe)'),
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
                title: const Text('Hands-free mode'),
                subtitle: const Text('Auto-start listening on open (wireframe).'),
              ),
              const SizedBox(height: AppTokens.sm),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _openConversation();
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Open full conversation view'),
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
    return AppStateBuilder(builder: (context, state) {
      final t = Theme.of(context).textTheme;

      // Wireframe behavior: if hands-free enabled, auto-start.
      if (state.handsFree && !_listening) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_listening) _toggle();
        });
      }

      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.lg),
            child: Column(
              children: [
                Row(
                  children: [
                    const AppLogoMark(),
                    const SizedBox(width: AppTokens.sm),
                    Expanded(
                      child: Text(
                        _status,
                        style: t.titleMedium,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openMoreSheet,
                      icon: const Icon(Icons.tune),
                      label: Text(state.voiceTone.label),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.lg),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppTokens.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Live caption', style: t.titleSmall),
                                  const SizedBox(height: AppTokens.sm),
                                  Text(
                                    _liveCaption.isEmpty ? 'Speak naturally. We will summarize and save.' : _liveCaption,
                                    style: t.headlineSmall?.copyWith(height: 1.2),
                                  ),
                                  const SizedBox(height: AppTokens.md),
                                  const _WaveformStub(),
                                  const SizedBox(height: AppTokens.sm),
                                  Text(
                                    'Saved automatically after you confirm (voice or tap).',
                                    style: t.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppTokens.lg),
                        _BigMicButton(
                          listening: _listening,
                          onTap: _toggle,
                        ),
                        const SizedBox(height: AppTokens.sm),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: _openConversation,
                              icon: const Icon(Icons.expand_less),
                              label: const Text('Details'),
                            ),
                            const SizedBox(width: AppTokens.sm),
                            TextButton.icon(
                              onPressed: _listening ? _toggle : null,
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: const Text('End'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.sm),
                Text(
                  'Tip: Say “fever”, “vomiting”, “rash”, or a medicine name to trigger clinician-style follow-ups.',
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

class _BigMicButton extends StatelessWidget {
  const _BigMicButton({required this.listening, required this.onTap});

  final bool listening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: listening ? 'Stop listening' : 'Start listening',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: listening ? Colors.red : Theme.of(context).colorScheme.primary,
            boxShadow: [
              BoxShadow(
                blurRadius: 24,
                color: Colors.black.withOpacity(0.18),
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(
            listening ? Icons.stop : Icons.mic,
            color: Colors.white,
            size: 44,
          ),
        ),
      ),
    );
  }
}

class _WaveformStub extends StatelessWidget {
  const _WaveformStub();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        'Waveform (wireframe)',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
