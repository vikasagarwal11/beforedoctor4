import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/components.dart';
import '../../../core/utils/format.dart';
import '../../assistant/screens/voice_assistant_screen.dart';
import '../../episodes/screens/create_episode_screen.dart';
import '../../episodes/screens/episode_detail_screen.dart';
import '../../events/screens/log_event_screen.dart';
import '../../conditions/screens/conditions_screen.dart';
import '../../food/screens/food_exposures_screen.dart';
import '../../medications/screens/medications_screen.dart';
import '../../search/screens/timeline_search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repo,
    required this.activeProfile,
    required this.onProfileChange,
  });

  final MockRepo repo;
  final PersonProfile activeProfile;
  final ValueChanged<PersonProfile> onProfileChange;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _episodeListState = 'normal'; // 'normal', 'loading', 'empty', 'error'

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final episodes = widget.repo.episodesForProfile(widget.activeProfile.id);
    final active = widget.repo.activeEpisodeForProfile(widget.activeProfile.id);

    return Scaffold(
      body: Stack(
        children: [
          ListView(
          padding: const EdgeInsets.all(AppTokens.md),
          children: [
            OfflineBanner(),
            const SizedBox(height: AppTokens.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.md),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LogEventScreen(
                              repo: widget.repo,
                              activeProfile: widget.activeProfile,
                              initialEpisode: widget.repo.activeEpisodeForProfile(widget.activeProfile.id),
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Quick log'),
                      ),
                    ),
                    const SizedBox(width: AppTokens.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => TimelineSearchScreen(repo: widget.repo, profile: widget.activeProfile)),
                        ),
                        icon: const Icon(Icons.search),
                        label: const Text('Search'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTokens.md),
            _TopRow(
              repo: widget.repo,
              activeProfile: widget.activeProfile,
              onProfileChange: widget.onProfileChange,
            ),
            const SizedBox(height: AppTokens.lg),
            if (active != null) ...[
              Text('Active episode', style: t.labelSmall),
              const SizedBox(height: AppTokens.sm),
              _ActiveEpisodeCard(
                episode: active,
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EpisodeDetailScreen(repo: widget.repo, episodeId: active.id),
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.xl),
            ] else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No active episode', style: t.titleMedium),
                      const SizedBox(height: AppTokens.sm),
                      Text(
                        'Start tracking when you begin a medication or vaccine. Reporting is optional and always under your control.',
                        style: t.bodySmall,
                      ),
                      const SizedBox(height: AppTokens.md),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => CreateEpisodeScreen(repo: widget.repo, profile: widget.activeProfile)),
                        ).then((_) => setState(() {})),
                        icon: const Icon(Icons.add),
                        label: const Text('Create episode'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.xl),
            ],
            Row(
              children: [
                Expanded(child: Text('Timeline', style: t.titleMedium)),
                IconButton(
                  tooltip: 'Search timeline',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TimelineSearchScreen(repo: widget.repo, profile: widget.activeProfile),
                    ),
                  ),
                  icon: const Icon(Icons.search),
                ),
                Flexible(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'normal', label: Text('Normal')),
                      ButtonSegment(value: 'loading', label: Text('Load')),
                      ButtonSegment(value: 'empty', label: Text('Empty')),
                    ],
                    selected: {_episodeListState},
                    onSelectionChanged: (Set<String> selection) {
                      setState(() => _episodeListState = selection.first);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.sm),
            if (_episodeListState == 'normal') ...[
              ...episodes.map((e) => _EpisodeRow(
                    episode: e,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => EpisodeDetailScreen(repo: widget.repo, episodeId: e.id)),
                    ),
                  )),
              // Temporarily disabled to debug black screen
              // const SizedBox(height: AppTokens.lg),
              // Text('Recent events', style: t.titleSmall),
              // const SizedBox(height: AppTokens.sm),
              // ..._buildTimelineEvents(),
            ]
            else if (_episodeListState == 'loading')
              Column(
                children: List.generate(3, (index) => Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.sm),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTokens.md),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 48,
                            height: 48,
                            child: Skeleton(height: 48, radius: AppTokens.rLg),
                          ),
                          const SizedBox(width: AppTokens.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Skeleton(height: 16),
                                const SizedBox(height: AppTokens.xs),
                                const SizedBox(
                                  width: 150,
                                  child: Skeleton(height: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )),
              )
            else if (_episodeListState == 'empty')
              InlineEmptyState(
                title: 'No episodes yet',
                subtitle: 'Start tracking by creating your first episode.',
                icon: Icons.assignment_outlined,
                action: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CreateEpisodeScreen(repo: widget.repo, profile: widget.activeProfile)),
                  ).then((_) => setState(() {})),
                  icon: const Icon(Icons.add),
                  label: const Text('Create episode'),
                ),
              )
            else // error
              InlineErrorState(
                title: 'Failed to load episodes',
                subtitle: 'Something went wrong while loading your episodes. Please try again.',
                onRetry: () => setState(() => _episodeListState = 'normal'),
              ),
            const SizedBox(height: 100),
          ],
        ),
        Positioned(
          right: AppTokens.md,
          bottom: AppTokens.md,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'Create episode',
                child: FloatingActionButton.small(
                  heroTag: 'createEpisodeFab',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CreateEpisodeScreen(repo: widget.repo, profile: widget.activeProfile)),
                  ).then((_) => setState(() {})),
                  child: const Icon(Icons.add),
                ),
              ),
              const SizedBox(height: AppTokens.md),
              Tooltip(
                message: 'Voice logging (wireframe)',
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VoiceAssistantScreen(repo: widget.repo, profile: widget.activeProfile),
                    ),
                  ),
                  icon: const Icon(Icons.mic),
                  label: const Text('Voice'),
                ),
              ),
            ],
          ),
        ),
        ],
      ),
    );
  }

  List<Widget> _buildTimelineEvents() {
    try {
      final timelineEvents = widget.repo.timelineForProfile(widget.activeProfile.id);
      if (timelineEvents.isEmpty) {
        return [
          Padding(
            padding: const EdgeInsets.all(AppTokens.md),
            child: Text('No events yet. Log your first event to see it here.', style: Theme.of(context).textTheme.bodySmall),
          ),
        ];
      }
      return timelineEvents.take(10).map((event) {
        Episode? episode;
        try {
          episode = widget.repo.episodes.firstWhere((e) => e.id == event.episodeId);
        } catch (_) {
          episode = null;
        }
        return _TimelineEventRow(
          event: event,
          onTap: episode != null
              ? () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => EpisodeDetailScreen(repo: widget.repo, episodeId: episode!.id)),
                  );
                }
              : () {},
        );
      }).toList();
    } catch (e) {
      // Return empty list if there's any error to prevent crash
      return [
        Padding(
          padding: const EdgeInsets.all(AppTokens.md),
          child: Text('Error loading events', style: Theme.of(context).textTheme.bodySmall),
        ),
      ];
    }
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({required this.repo, required this.activeProfile, required this.onProfileChange});

  final MockRepo repo;
  final PersonProfile activeProfile;
  final ValueChanged<PersonProfile> onProfileChange;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Timeline', style: t.titleLarge),
              const SizedBox(height: AppTokens.xs),
              Text('Episode-based tracking, voice-first logging, privacy-first controls.', style: t.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: AppTokens.sm),
        _ProfilePicker(repo: repo, activeProfile: activeProfile, onProfileChange: onProfileChange),
      ],
    );
  }
}

class _ProfilePicker extends StatelessWidget {
  const _ProfilePicker({required this.repo, required this.activeProfile, required this.onProfileChange});

  final MockRepo repo;
  final PersonProfile activeProfile;
  final ValueChanged<PersonProfile> onProfileChange;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<PersonProfile>(
        value: activeProfile,
        items: repo.profiles
            .map((p) => DropdownMenuItem(
                  value: p,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        child: Text(p.displayName.substring(0, 1)),
                      ),
                      const SizedBox(width: AppTokens.sm),
                      Text('${p.displayName} • ${p.ageLabel}'),
                    ],
                  ),
                ))
            .toList(),
        onChanged: (p) {
          if (p != null) onProfileChange(p);
        },
      ),
    );
  }
}

class _ActiveEpisodeCard extends StatelessWidget {
  const _ActiveEpisodeCard({required this.episode, required this.onOpen});

  final Episode episode;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.rLg),
      onTap: onOpen,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(episode.productName, style: t.titleMedium)),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: AppTokens.xs),
              Text('${episode.productType} • Started ${formatShortDate(episode.startAt)}', style: t.bodySmall),
              const SizedBox(height: AppTokens.md),
              Wrap(
                spacing: AppTokens.sm,
                runSpacing: AppTokens.sm,
                children: [
                  StatusChip(label: dayCounterLabel(episode.startAt), icon: Icons.timelapse, color: AppColors.primary),
                  StatusChip(
                    label: episode.monitoringOn ? 'Monitoring on' : 'Monitoring off',
                    icon: episode.monitoringOn ? Icons.notifications_active : Icons.notifications_off,
                    color: episode.monitoringOn ? AppColors.success : AppColors.textSecondary,
                  ),
                  StatusChip(
                    label: episode.watchlistOn ? 'Watchlist on' : 'Watchlist off',
                    icon: Icons.visibility_outlined,
                    color: episode.watchlistOn ? AppColors.primary : AppColors.textSecondary,
                  ),
                  StatusChip(
                    label: episode.sharePVDefault ? 'PV share on' : 'PV share off',
                    icon: Icons.shield_outlined,
                    color: episode.sharePVDefault ? AppColors.warning : AppColors.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode, required this.onTap});

  final Episode episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final status = episode.status == EpisodeStatus.active ? 'Active' : 'Completed';
    final statusColor = episode.status == EpisodeStatus.active ? AppColors.success : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        onTap: onTap,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.md),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.12),
                  child: Icon(
                    episode.productType == 'Vaccine' ? Icons.vaccines_outlined : Icons.medication_outlined,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: AppTokens.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(episode.productName, style: t.bodyLarge),
                      const SizedBox(height: AppTokens.xs),
                      Text('${episode.productType} • ${formatShortDate(episode.startAt)} • $status', style: t.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineEventRow extends StatelessWidget {
  const _TimelineEventRow({required this.event, required this.onTap});

  final EpisodeEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final icon = switch (event.type) {
      EventType.symptom => Icons.sick_outlined,
      EventType.medicationIssue => Icons.medication_outlined,
      EventType.vaccineReaction => Icons.vaccines_outlined,
      EventType.note => Icons.note_outlined,
    };
    final color = switch (event.type) {
      EventType.symptom => AppColors.warning,
      EventType.medicationIssue => AppColors.danger,
      EventType.vaccineReaction => AppColors.primary,
      EventType.note => AppColors.textSecondary,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        onTap: onTap,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.md),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: AppTokens.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title, style: t.bodyMedium),
                      const SizedBox(height: AppTokens.xs),
                      Text(
                        formatShortDate(event.timestamp),
                        style: t.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (event.severity != null) ...[
                  const SizedBox(width: AppTokens.sm),
                  StatusChip(
                    label: '${event.severity}/10',
                    icon: Icons.signal_cellular_alt_outlined,
                    color: color,
                  ),
                ],
                const SizedBox(width: AppTokens.xs),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({required this.repo, required this.profileId});

  final MockRepo repo;
  final String profileId;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quick actions', style: t.titleMedium),
            const SizedBox(height: AppTokens.sm),
            Wrap(
              spacing: AppTokens.sm,
              runSpacing: AppTokens.sm,
              children: [
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VoiceAssistantScreen(repo: repo, profile: repo.getProfile(profileId)),
                    ),
                  ),
                  icon: const Icon(Icons.mic),
                  label: const Text('Log anything'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => FoodExposuresScreen(repo: repo, profileId: profileId)),
                  ),
                  icon: const Icon(Icons.restaurant_outlined),
                  label: const Text('Food & triggers'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ConditionsScreen(repo: repo, profile: repo.getProfile(profileId))),
                  ),
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('Conditions'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MedicationsScreen(repo: repo, profile: repo.getProfile(profileId))),
                  ),
                  icon: const Icon(Icons.medication_outlined),
                  label: const Text('Meds & remedies'),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.xs),
            Text(
              'The timeline is your medical diary. Log symptoms, foods, meds, remedies, and notes—then link items to find patterns over time.',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
