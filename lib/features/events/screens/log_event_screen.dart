import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/components.dart';
import '../../../core/utils/format.dart';

class LogEventScreen extends StatefulWidget {
  const LogEventScreen({
    super.key,
    required this.repo,
    required this.activeProfile,
    required this.initialEpisode,
  });

  final MockRepo repo;
  final PersonProfile activeProfile;
  final Episode? initialEpisode;

  @override
  State<LogEventScreen> createState() => _LogEventScreenState();
}

class _LogEventScreenState extends State<LogEventScreen> {
  bool _isRecording = true; // We enter from mic
  String _transcript = '';
  final _controller = TextEditingController();

  final List<String> _allTags = const [
    'Fever',
    'Cough',
    'Rash',
    'Nausea',
    'Vaccine',
    'Medication',
    'Sleep',
    'Mood',
    'Appetite',
    'Pain',
  ];
  final Set<String> _selected = {};

  EventType _type = EventType.symptom;
  double _severity = 4;
  bool _redFlag = false;
  bool _queuedOffline = false;
  bool _shareClinician = false;

  @override
  void initState() {
    super.initState();
    // Fake transcription (wireframe) after a short delay.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _transcript = 'Fever 101.2 after dose, seems tired and less appetite.';
        _controller.text = _transcript;
        _selected.addAll(['Fever', 'Medication', 'Appetite']);
        _isRecording = false;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Episode _resolveEpisodeOrCreate() {
    final ep = widget.initialEpisode;
    if (ep != null) return ep;

    // If no active episode, create a lightweight "General episode" wireframe.
    final newEp = Episode(
      id: 'e_${DateTime.now().millisecondsSinceEpoch}',
      profileId: widget.activeProfile.id,
      productName: 'General health log',
      productType: 'Medication',
      startAt: DateTime.now(),
      status: EpisodeStatus.active,
    );
    widget.repo.episodes.insert(0, newEp);
    return newEp;
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final ep = _resolveEpisodeOrCreate();

    final ev = EpisodeEvent(
      id: 'ev_${DateTime.now().millisecondsSinceEpoch}',
      episodeId: ep.id,
      type: _type,
      title: text.length > 64 ? '${text.substring(0, 64)}…' : text,
      timestamp: DateTime.now(),
      severity: _type == EventType.note ? null : _severity.round(),
      sharedToClinician: _shareClinician,
      queuedOffline: _queuedOffline,
    );

    widget.repo.addEvent(ev);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log event'),
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.md),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Voice-first capture', style: t.titleMedium),
                  const SizedBox(height: AppTokens.sm),
                  Text(
                    'This is a UI wireframe: waveform + transcript are simulated. In production, this connects to on-device/streaming ASR.',
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: AppTokens.md),
                  Container(
                    padding: const EdgeInsets.all(AppTokens.md),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTokens.rMd),
                      border: Border.all(color: scheme.outlineVariant),
                      color: scheme.surfaceContainerHighest.withOpacity(0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(_isRecording ? Icons.fiber_manual_record : Icons.check_circle, color: _isRecording ? AppColors.danger : AppColors.success),
                            const SizedBox(width: AppTokens.sm),
                            Text(_isRecording ? 'Recording…' : 'Transcript ready', style: t.bodyLarge),
                            const Spacer(),
                            Text(_isRecording ? 'Listening' : 'Review', style: t.labelSmall),
                          ],
                        ),
                        const SizedBox(height: AppTokens.md),
                        FakeWaveform(isActive: _isRecording),
                        const SizedBox(height: AppTokens.md),
                        TextField(
                          controller: _controller,
                          minLines: 2,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'Transcript / notes',
                            hintText: 'Describe what happened…',
                            prefixIcon: Icon(Icons.edit_outlined),
                          ),
                        ),
                        const SizedBox(height: AppTokens.md),
                        Wrap(
                          spacing: AppTokens.sm,
                          runSpacing: AppTokens.sm,
                          children: _allTags.map((tag) {
                            final selected = _selected.contains(tag);
                            return FilterChip(
                              selected: selected,
                              label: Text(tag),
                              onSelected: (v) => setState(() => v ? _selected.add(tag) : _selected.remove(tag)),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
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
                  const SectionHeader(title: 'Structured details'),
                  const SizedBox(height: AppTokens.sm),
                  DropdownButtonFormField<EventType>(
                    value: _type,
                    decoration: const InputDecoration(
                      labelText: 'Event type',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: EventType.symptom, child: Text('Symptom')),
                      DropdownMenuItem(value: EventType.medicationIssue, child: Text('Medication issue')),
                      DropdownMenuItem(value: EventType.vaccineReaction, child: Text('Vaccine reaction')),
                      DropdownMenuItem(value: EventType.note, child: Text('General note')),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? _type),
                  ),
                  const SizedBox(height: AppTokens.md),
                  if (_type != EventType.note) ...[
                    Text('Severity', style: t.bodyLarge),
                    const SizedBox(height: AppTokens.xs),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _severity,
                            min: 0,
                            max: 10,
                            divisions: 10,
                            label: _severity.round().toString(),
                            onChanged: (v) => setState(() => _severity = v),
                          ),
                        ),
                        Container(
                          width: 44,
                          alignment: Alignment.centerRight,
                          child: Text('${_severity.round()}/10', style: t.bodyLarge),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.sm),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Red-flag indicator (wireframe)'),
                      subtitle: const Text('Example: trouble breathing, swelling, fainting'),
                      value: _redFlag,
                      onChanged: (v) => setState(() => _redFlag = v),
                    ),
                    if (_redFlag)
                      Container(
                        padding: const EdgeInsets.all(AppTokens.md),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(AppTokens.rMd),
                          border: Border.all(color: AppColors.danger.withOpacity(0.35)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                            const SizedBox(width: AppTokens.sm),
                            Expanded(
                              child: Text(
                                'Consider urgent medical care. This app does not provide a diagnosis.',
                                style: t.bodySmall?.copyWith(color: AppColors.danger),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: AppTokens.md),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Queue offline'),
                    subtitle: const Text('Simulates offline-first behavior'),
                    value: _queuedOffline,
                    onChanged: (v) => setState(() => _queuedOffline = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mark as shared to clinician'),
                    subtitle: const Text('UI-only: does not send anything'),
                    value: _shareClinician,
                    onChanged: (v) => setState(() => _shareClinician = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.lg),
          FilledButton.icon(
            onPressed: _controller.text.trim().isEmpty ? null : _save,
            icon: const Icon(Icons.save),
            label: const Text('Save event'),
          ),
          const SizedBox(height: AppTokens.sm),
          Text(
            'Saved events appear in the episode timeline with offline/share badges.',
            style: t.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTokens.lg),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.md, vertical: AppTokens.sm),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 18),
              const SizedBox(width: AppTokens.sm),
              Expanded(
                child: Text(
                  _isRecording ? 'Audio stays on device in this wireframe.' : 'No data leaves your device in this wireframe.',
                  style: t.bodySmall,
                ),
              ),
              Text(formatTime(DateTime.now()), style: t.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
