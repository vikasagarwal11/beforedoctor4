import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/components.dart';
import '../../../shared/widgets/states.dart';
import '../../../core/utils/format.dart';
import '../../events/screens/log_event_screen.dart';
import '../../share/screens/share_screen.dart';

class EpisodeDetailScreen extends StatefulWidget {
  const EpisodeDetailScreen({super.key, required this.repo, required this.episodeId});

  final MockRepo repo;
  final String episodeId;

  @override
  State<EpisodeDetailScreen> createState() => _EpisodeDetailScreenState();
}

class _EpisodeDetailScreenState extends State<EpisodeDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final episode = widget.repo.episodes.firstWhere((e) => e.id == widget.episodeId);
    final profile = widget.repo.getProfile(episode.profileId);
    final events = widget.repo.eventsForEpisode(episode.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(episode.productName),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ShareScreen(repo: widget.repo, episodeId: episode.id)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.md),
        children: [
          const OfflineBanner(),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${episode.productType} • ${profile.displayName}', style: t.bodySmall),
                  const SizedBox(height: AppTokens.xs),
                  Text('Started ${formatShortDate(episode.startAt)}', style: t.titleMedium),
                  const SizedBox(height: AppTokens.md),
                  Wrap(
                    spacing: AppTokens.sm,
                    runSpacing: AppTokens.sm,
                    children: [
                      StatusChip(label: dayCounterLabel(episode.startAt), icon: Icons.timelapse),
                      StatusChip(
                        label: episode.monitoringOn ? 'Monitoring on' : 'Monitoring off',
                        icon: episode.monitoringOn ? Icons.notifications_active : Icons.notifications_off,
                        color: episode.monitoringOn ? AppColors.success : AppColors.textSecondary,
                        onTap: () => setState(() => episode.monitoringOn = !episode.monitoringOn),
                      ),
                      StatusChip(
                        label: episode.watchlistOn ? 'Watchlist on' : 'Watchlist off',
                        icon: Icons.visibility_outlined,
                        color: episode.watchlistOn ? AppColors.primary : AppColors.textSecondary,
                        onTap: () => setState(() => episode.watchlistOn = !episode.watchlistOn),
                      ),
                      StatusChip(
                        label: episode.sharePVDefault ? 'PV share on' : 'PV share off',
                        icon: Icons.shield_outlined,
                        color: episode.sharePVDefault ? AppColors.warning : AppColors.textSecondary,
                        onTap: () => setState(() => episode.sharePVDefault = !episode.sharePVDefault),
                      ),
                    ],
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
                  const SectionHeader(title: 'Episode timeline'),
                  const SizedBox(height: AppTokens.sm),
                  Text(
                    'This wireframe shows how the timeline will feel. In production, events are structured and can be exported as a clinician summary.',
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: AppTokens.md),
                  ...events.map((e) => _EventRow(event: e)),
                  if (events.isEmpty) Text('No events yet.', style: t.bodySmall),
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
                  const SectionHeader(title: 'Insights (preview)'),
                  const SizedBox(height: AppTokens.sm),
                  _InsightTile(
                    title: 'Most common theme',
                    subtitle: events.isEmpty ? '—' : 'Symptom trend appears after dosing window.',
                    icon: Icons.auto_graph_outlined,
                  ),
                  const SizedBox(height: AppTokens.sm),
                  _InsightTile(
                    title: 'Next check-in',
                    subtitle: 'Tomorrow morning (Supportive cadence)',
                    icon: Icons.schedule_outlined,
                  ),
                  const SizedBox(height: AppTokens.sm),
                  _InsightTile(
                    title: 'Safety watchlist',
                    subtitle: episode.watchlistOn ? 'Enabled for this episode' : 'Disabled',
                    icon: Icons.visibility_outlined,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => LogEventScreen(
                  repo: widget.repo,
                  activeProfile: profile,
                  initialEpisode: episode,
                ),
              ),
            )
            .then((_) => setState(() {})),
        icon: const Icon(Icons.mic),
        label: const Text('Log event'),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final EpisodeEvent event;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            child: Icon(iconForEventType(event.type), size: 18),
          ),
          const SizedBox(width: AppTokens.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: t.bodyLarge),
                const SizedBox(height: AppTokens.xs),
                Text('${formatShortDate(event.timestamp)} • ${formatTime(event.timestamp)}', style: t.bodySmall),
                if (event.severity != null) ...[
                  const SizedBox(height: AppTokens.xs),
                  Text('Severity: ${event.severity}/10', style: t.labelSmall),
                ],
                const SizedBox(height: AppTokens.xs),
                Wrap(
                  spacing: AppTokens.sm,
                  runSpacing: AppTokens.sm,
                  children: [
                    if (event.sharedToClinician)
                      const StatusChip(label: 'Shared to clinician', icon: Icons.verified, color: AppColors.success),
                    if (event.queuedOffline)
                      const StatusChip(label: 'Queued offline', icon: Icons.cloud_off, color: AppColors.textSecondary),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.title, required this.subtitle, required this.icon});

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
      ),
      child: Row(
        children: [
          Icon(icon),
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
