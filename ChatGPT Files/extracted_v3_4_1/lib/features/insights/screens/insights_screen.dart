import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/components.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key, required this.repo, required this.profile});

  final MockRepo repo;
  final PersonProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final active = repo.activeEpisodeForProfile(profile.id);
    final events = active == null ? <EpisodeEvent>[] : repo.eventsForEpisode(active.id);

    return ListView(
      padding: const EdgeInsets.all(AppTokens.md),
      children: [
        Text('Insights', style: t.titleLarge),
        const SizedBox(height: AppTokens.xs),
        Text('Wireframe analytics and summaries (no algorithms enabled).', style: t.bodySmall),
        const SizedBox(height: AppTokens.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Current episode summary'),
                const SizedBox(height: AppTokens.sm),
                if (active == null)
                  Text('No active episode. Start one to see insights.', style: t.bodySmall)
                else ...[
                  Text(active.productName, style: t.titleMedium),
                  const SizedBox(height: AppTokens.xs),
                  Text('Events logged: ${events.length}', style: t.bodySmall),
                  const SizedBox(height: AppTokens.md),
                  _MetricRow(label: 'Estimated follow-up burden', value: events.isEmpty ? 'Low' : 'Moderate'),
                  const SizedBox(height: AppTokens.sm),
                  _MetricRow(label: 'Suggested cadence', value: active.monitoringOn ? 'Day 1–7 adaptive' : 'Off'),
                  const SizedBox(height: AppTokens.sm),
                  _MetricRow(label: 'PV eligibility (preview)', value: active.sharePVDefault ? 'Enabled' : 'Opt-in'),
                ],
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
                const SectionHeader(title: 'Trend cards'),
                const SizedBox(height: AppTokens.sm),
                _TrendCard(title: 'Symptom timing', subtitle: 'After dosing window (placeholder)'),
                const SizedBox(height: AppTokens.sm),
                _TrendCard(title: 'Severity distribution', subtitle: 'Most events 2–5/10 (placeholder)'),
                const SizedBox(height: AppTokens.sm),
                _TrendCard(title: 'Potential triggers', subtitle: 'Food/sleep correlation (placeholder)'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: t.bodySmall)),
        Text(value, style: t.labelSmall),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.rMd),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.stacked_line_chart_outlined),
          const SizedBox(width: AppTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.bodyLarge),
                const SizedBox(height: AppTokens.xs),
                Text(subtitle, style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
