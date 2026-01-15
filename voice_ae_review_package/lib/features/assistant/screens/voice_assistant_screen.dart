import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_state.dart';
import '../../../core/constants/tokens.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/components.dart';
import '../../pv/screens/ae_report_preview_screen.dart';

enum _AssistantPhase { idle, listening, transcribing, clarifying, readyToSave, saving }

enum _LogIntent { general, fever, vomiting, rash, medicationSideEffect }

extension _LogIntentLabel on _LogIntent {
  String get label {
    switch (this) {
      case _LogIntent.general:
        return 'General';
      case _LogIntent.fever:
        return 'Fever';
      case _LogIntent.vomiting:
        return 'Vomiting';
      case _LogIntent.rash:
        return 'Rash';
      case _LogIntent.medicationSideEffect:
        return 'Medication side effect';
    }
  }
}

class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen({super.key, required this.repo, required this.profile});

  final MockRepo repo;
  final PersonProfile profile;

  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> {
  _AssistantPhase _phase = _AssistantPhase.idle;
  _LogIntent _intent = _LogIntent.general;
  bool _continuous = true;
  bool _speakToConfirm = true;
  bool _pvDraftReady = false;

  final List<_ChatTurn> _turns = [
    _ChatTurn.assistant(
      "Tell me what happened. You can speak naturally, and I'll capture it as a medical diary entry with a few follow-ups.",
    ),
  ];

  // Wireframe draft extraction.
  final Map<String, String> _draft = {
    'Profile': '',
    'Primary symptom': '',
    'Severity': '',
    'Onset': '',
    'Meds taken': '',
    'Food/exposure': '',
    'Notes': '',
  };

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _setIntent(_intent);
    _draft['Profile'] = widget.profile.displayName;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _setIntent(_LogIntent intent) {
    setState(() {
      _intent = intent;
      _pvDraftReady = intent == _LogIntent.medicationSideEffect;
      _draft.clear();
      _draft['Profile'] = widget.profile.displayName;
      _draft['Primary symptom'] = switch (intent) {
        _LogIntent.fever => 'Fever',
        _LogIntent.vomiting => 'Vomiting',
        _LogIntent.rash => 'Rash',
        _LogIntent.medicationSideEffect => 'Upset stomach',
        _ => '—',
      };
      _draft['Onset'] = '—';
      _draft['Severity'] = '—';
      _draft['Meds taken'] = '—';
      _draft['Food/exposure'] = '—';
      _draft['Notes'] = '—';
    });
  }

  List<String> _quickAnswersForIntent(_LogIntent intent) {
    switch (intent) {
      case _LogIntent.fever:
        return const ['101.2°F', '102.4°F', 'Since 3pm', 'Given Tylenol', 'No rash', 'Mild cough'];
      case _LogIntent.vomiting:
        return const ['2 times', 'Since morning', 'After dairy', 'No fever', 'Mild belly pain', 'Keeping fluids'];
      case _LogIntent.rash:
        return const ['Itchy', 'Non-itchy', 'Started today', 'After new food', 'After antibiotic', 'Spreading'];
      case _LogIntent.medicationSideEffect:
        return const ['Advil', 'Tylenol', 'Dose: 200mg', 'Started 1h after', 'Improving', 'Not improving'];
      case _LogIntent.general:
        return const ['Started today', 'Mild', 'Moderate', 'Severe', 'Improving', 'Worsening'];
    }
  }

  String _followupPromptForIntent(_LogIntent intent) {
    switch (intent) {
      case _LogIntent.fever:
        return 'Thanks. What was the temperature, when did it start, and did you give any medicine? Any cough, rash, vomiting, or trouble breathing?';
      case _LogIntent.vomiting:
        return 'Understood. How many times, when did it start, any fever or belly pain, and what did you eat or drink before it started? Any dehydration signs?';
      case _LogIntent.rash:
        return 'Got it. Where is the rash, is it itchy, when did it start, and any new foods, soaps, medicines, or vaccines recently? Any swelling or breathing issues?';
      case _LogIntent.medicationSideEffect:
        return 'Thanks. Which medicine did you take, the dose and time, when the symptoms started, and how are you feeling now? Any other meds taken the same day?';
      case _LogIntent.general:
        return 'Thanks. When did it start, how severe is it, and what else is happening that might be related?';
    }
  }

  void _startListening() {
    if (_phase != _AssistantPhase.idle && _phase != _AssistantPhase.readyToSave) return;

    setState(() {
      _phase = _AssistantPhase.listening;
    });

    // Simulate: listening -> transcribing -> assistant follow-up.
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      setState(() => _phase = _AssistantPhase.transcribing);
      _timer = Timer(const Duration(seconds: 2), () {
        final userSaid = switch (_intent) {
          _LogIntent.fever => 'My son has a fever since after school. I gave Tylenol and he seems a bit better.',
          _LogIntent.vomiting => 'My son vomited twice this morning and says his stomach hurts a bit.',
          _LogIntent.rash => 'My son developed a rash on his arms today and it looks a bit itchy.',
          _LogIntent.medicationSideEffect => 'I took Advil yesterday and I got an upset stomach afterwards.',
          _ => 'I want to log a health update.',
        };
        setState(() {
          _turns.add(_ChatTurn.user(userSaid));
          _turns.add(_ChatTurn.assistant(_followupPromptForIntent(_intent)));
          _phase = _AssistantPhase.clarifying;

          // Update draft (wireframe).
          _draft['Primary symptom'] = _draft['Primary symptom'] ?? '—';
          _draft['Notes'] = switch (_intent) {
            _LogIntent.fever => 'After school; improved after Tylenol (reported).',
            _LogIntent.vomiting => '2 episodes reported; mild belly pain.',
            _LogIntent.rash => 'Rash on arms; itchy (reported).',
            _LogIntent.medicationSideEffect => 'Upset stomach after Advil (reported).',
            _ => 'General update logged.',
          };
          _draft['Meds taken'] = switch (_intent) {
            _LogIntent.fever => 'Tylenol (reported)',
            _LogIntent.medicationSideEffect => 'Advil (reported)',
            _ => _draft['Meds taken'] ?? '—',
          };
        });
      });
    });
  }

  void _answerQuick(String answer) {
    if (_phase != _AssistantPhase.clarifying) return;
    setState(() {
      _turns.add(_ChatTurn.user(answer));
      _turns.add(_ChatTurn.assistant(
          'Got it. I can save this as a structured timeline entry and include a doctor-ready summary. Would you like to add the temperature and exact time, or save now?'));
      _phase = _AssistantPhase.readyToSave;

      // Update draft with a plausible structured completion.
      if (answer.toLowerCase().contains('101') || answer.toLowerCase().contains('102')) {
        _draft['Severity'] = answer.contains('°F') ? answer : '$answer (reported)';
      }
      if (answer.toLowerCase().contains('pm') || answer.toLowerCase().contains('am') || answer.toLowerCase().contains('since')) {
        _draft['Onset'] = answer;
      }
    });
  }

  void _save() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved to Timeline (wireframe).')),
    );
    setState(() {
      _phase = _AssistantPhase.idle;
      if (_continuous) {
        _turns.add(_ChatTurn.assistant(
            "Saved. Anything else you want to add? You can keep speaking."));
      } else {
        _turns.add(_ChatTurn.assistant(
            "Saved. If you want, you can say: 'Generate doctor report for last 7 days' or 'Report this as an adverse event'."));
      }
    });
  }

  void _confirmAndSave() {
    if (_phase != _AssistantPhase.readyToSave) return;
    setState(() => _phase = _AssistantPhase.saving);
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() => _phase = _AssistantPhase.idle);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to timeline (wireframe).')),
      );
      if (_continuous) {
        setState(() {
          _turns.add(_ChatTurn.assistant('Saved. Anything else you want to add? You can keep speaking.'));
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice diary'),
        actions: [
          _ToneDropdown(
            value: appState.voiceTone,
            onChanged: (v) => appState.setVoiceTone(v),
          ),
          const SizedBox(width: AppTokens.xs),
        ],
      ),
      body: Column(
        children: [
          _ModelRoutingBar(phase: _phase),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppTokens.md),
              children: [
                if (_phase == _AssistantPhase.idle) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Quick start', style: t.titleMedium),
                          const SizedBox(height: AppTokens.sm),
                          Wrap(
                            spacing: AppTokens.xs,
                            runSpacing: AppTokens.xs,
                            children: _LogIntent.values.map((intent) {
                              final selected = _intent == intent;
                              return FilterChip(
                                label: Text(intent.label),
                                selected: selected,
                                onSelected: (v) => _setIntent(intent),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTokens.md),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Settings', style: t.titleMedium),
                          const SizedBox(height: AppTokens.sm),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _continuous,
                            onChanged: (v) => setState(() => _continuous = v),
                            title: const Text('Continuous mode'),
                            subtitle: const Text('Keep conversation active after save for multi-turn logging.'),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _speakToConfirm,
                            onChanged: (v) => setState(() => _speakToConfirm = v),
                            title: const Text('Confirm by voice'),
                            subtitle: const Text('Use voice confirmation instead of button tap.'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTokens.md),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Draft extraction', style: t.titleMedium),
                        const SizedBox(height: AppTokens.xs),
                        Text(
                          'Wireframe: this panel shows what the system extracted from your voice. In production this is created by a multi-model pipeline (STT + extraction + clinician follow-ups).',
                          style: t.bodySmall,
                        ),
                        const SizedBox(height: AppTokens.md),
                        ..._draft.entries.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: AppTokens.xs),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 120,
                                    child: Text(e.key, style: t.bodySmall),
                                  ),
                                  Expanded(
                                    child: Text(e.value, style: t.bodyMedium),
                                  ),
                                ],
                              ),
                            )),
                        const SizedBox(height: AppTokens.sm),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Edit draft via voice (wireframe).')),
                              ),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit'),
                            ),
                            const SizedBox(width: AppTokens.sm),
                            if (_speakToConfirm && _phase == _AssistantPhase.readyToSave)
                              FilledButton.icon(
                                onPressed: _confirmAndSave,
                                icon: const Icon(Icons.mic),
                                label: const Text('Simulate: Say "Confirm"'),
                              )
                            else
                              FilledButton.icon(
                                onPressed: _phase == _AssistantPhase.readyToSave ? _save : null,
                                icon: const Icon(Icons.check),
                                label: const Text('Confirm & save'),
                              ),
                            if (_pvDraftReady && _phase == _AssistantPhase.readyToSave) ...[
                              const SizedBox(width: AppTokens.sm),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AEReportPreviewScreen(
                                        profileName: widget.profile.displayName,
                                        suspectedProduct: _draft['Meds taken'] ?? 'Unknown',
                                        eventSummary: _draft['Primary symptom'] ?? 'Adverse event',
                                        narrative: _draft['Notes'] ?? '',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.preview_outlined),
                                label: const Text('Preview AE report'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.md),
                Text('Conversation', style: t.titleSmall),
                const SizedBox(height: AppTokens.sm),
                ..._turns.map((turn) => _ChatBubble(turn: turn)),
                const SizedBox(height: AppTokens.lg),
              ],
            ),
          ),
          _BottomVoiceBar(
            phase: _phase,
            intent: _intent,
            onMic: _startListening,
            onQuickAnswer: _answerQuick,
            quickAnswers: _quickAnswersForIntent(_intent),
          ),
        ],
      ),
    );
  }
}

class _ModelRoutingBar extends StatelessWidget {
  const _ModelRoutingBar({required this.phase});

  final _AssistantPhase phase;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    String status = switch (phase) {
      _AssistantPhase.idle => 'Ready',
      _AssistantPhase.listening => 'Listening',
      _AssistantPhase.transcribing => 'Transcribing',
      _AssistantPhase.clarifying => 'Clarifying',
      _AssistantPhase.readyToSave => 'Ready to save',
      _AssistantPhase.saving => 'Saving',
    };

    return Material(
      elevation: 0,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.md, vertical: AppTokens.sm),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          children: [
            StatusChip(label: status, icon: Icons.bolt, color: AppColors.primary),
            const SizedBox(width: AppTokens.sm),
            Expanded(
              child: Text(
                'Model routing (wireframe): STT + Extract + Dialogue + PV',
                style: t.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomVoiceBar extends StatelessWidget {
  const _BottomVoiceBar({
    required this.phase,
    required this.intent,
    required this.onMic,
    required this.onQuickAnswer,
    required this.quickAnswers,
  });

  final _AssistantPhase phase;
  final _LogIntent intent;
  final VoidCallback onMic;
  final void Function(String answer) onQuickAnswer;
  final List<String> quickAnswers;

  @override
  Widget build(BuildContext context) {
    final isBusy = phase == _AssistantPhase.listening || phase == _AssistantPhase.transcribing || phase == _AssistantPhase.saving;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(AppTokens.md),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (phase == _AssistantPhase.clarifying) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: AppTokens.xs,
                  runSpacing: AppTokens.xs,
                  children: quickAnswers.take(6).map((answer) {
                    return OutlinedButton(
                      onPressed: () => onQuickAnswer(answer),
                      child: Text(answer),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: AppTokens.sm),
            ],
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isBusy ? null : onMic,
                    icon: const Icon(Icons.mic),
                    label: Text(isBusy ? 'Working...' : 'Hold / Tap to speak'),
                  ),
                ),
                const SizedBox(width: AppTokens.sm),
                IconButton(
                  tooltip: 'Type (wireframe)',
                  onPressed: () => ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Typed input (wireframe).'))),
                  icon: const Icon(Icons.keyboard_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToneDropdown extends StatelessWidget {
  const _ToneDropdown({required this.value, required this.onChanged});

  final VoiceTone value;
  final ValueChanged<VoiceTone> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<VoiceTone>(
        value: value,
        alignment: Alignment.centerRight,
        icon: const Icon(Icons.expand_more),
        items: VoiceTone.values
            .map(
              (v) => DropdownMenuItem(
                value: v,
                child: Text(v.label, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _ChatTurn {
  _ChatTurn._(this.role, this.text);

  final String role; // 'user' | 'assistant'
  final String text;

  static _ChatTurn user(String text) => _ChatTurn._('user', text);
  static _ChatTurn assistant(String text) => _ChatTurn._('assistant', text);
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.turn});

  final _ChatTurn turn;

  @override
  Widget build(BuildContext context) {
    final isUser = turn.role == 'user';
    final t = Theme.of(context).textTheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.only(bottom: AppTokens.sm),
        padding: const EdgeInsets.all(AppTokens.md),
        decoration: BoxDecoration(
          color: isUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTokens.lg),
        ),
        child: Text(turn.text, style: t.bodyMedium),
      ),
    );
  }
}
