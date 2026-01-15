import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../shared/widgets/components.dart';
import '../../../core/utils/format.dart';

class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key, required this.repo, required this.episodeId});

  final MockRepo repo;
  final String episodeId;

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  bool _includeTimeline = true;
  bool _includeSeverity = true;
  bool _includePhotos = false; // not implemented
  bool _shareClinician = true;
  bool _sharePV = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ep = widget.repo.episodes.firstWhere((e) => e.id == widget.episodeId);
    final events = widget.repo.eventsForEpisode(ep.id);

    return Scaffold(
      appBar: AppBar(title: const Text('Share summary')),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.md),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Preview', style: t.titleMedium),
                  const SizedBox(height: AppTokens.sm),
                  Text(
                    'In production, this generates a clinician-friendly PDF and optionally a de-identified PV submission package. This wireframe shows the UI only.',
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: AppTokens.md),
                  Container(
                    padding: const EdgeInsets.all(AppTokens.md),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTokens.rMd),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${ep.productName} • ${formatShortDate(ep.startAt)}', style: t.bodyLarge),
                        const SizedBox(height: AppTokens.xs),
                        Text('Events: ${events.length}', style: t.bodySmall),
                        const SizedBox(height: AppTokens.sm),
                        Text(
                          'Summary: Symptoms captured during exposure window. Patient-reported severity included as selected.',
                          style: t.bodySmall,
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
                  const SectionHeader(title: 'Include'),
                  const SizedBox(height: AppTokens.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Timeline'),
                    subtitle: const Text('List of events with timestamps'),
                    value: _includeTimeline,
                    onChanged: (v) => setState(() => _includeTimeline = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Severity'),
                    subtitle: const Text('Include 0–10 patient scoring'),
                    value: _includeSeverity,
                    onChanged: (v) => setState(() => _includeSeverity = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Photos'),
                    subtitle: const Text('Rash/injury images (placeholder)'),
                    value: _includePhotos,
                    onChanged: (v) => setState(() => _includePhotos = v),
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
                  const SectionHeader(title: 'Share targets'),
                  const SizedBox(height: AppTokens.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Clinician'),
                    subtitle: const Text('Email / portal / export (wireframe)'),
                    value: _shareClinician,
                    onChanged: (v) => setState(() => _shareClinician = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('De-identified PV'),
                    subtitle: const Text('Regulator / sponsor (wireframe)'),
                    value: _sharePV,
                    onChanged: (v) => setState(() => _sharePV = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.lg),
          FilledButton.icon(
            onPressed: () => _snack(context, 'Share initiated (wireframe).'),
            icon: const Icon(Icons.send),
            label: const Text('Share'),
          ),
        ],
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
