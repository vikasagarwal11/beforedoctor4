import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/components.dart';
import '../../../core/utils/format.dart';

class FoodExposuresScreen extends StatelessWidget {
  const FoodExposuresScreen({super.key, required this.repo, required this.profileId});

  final MockRepo repo;
  final String profileId;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final foods = repo.foodLogsForProfile(profileId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Food & exposures'),
        actions: [
          IconButton(
            tooltip: 'Add (wireframe)',
            onPressed: () => _snack(context, 'Add food/exposure (wireframe).'),
            icon: const Icon(Icons.add),
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
                  Text('Track triggers', style: t.titleMedium),
                  const SizedBox(height: AppTokens.xs),
                  Text(
                    'Log foods and exposures to help identify patterns (e.g., dairy and stomach ache). Link them to symptoms in the timeline.',
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.md),
          if (foods.isEmpty)
            InlineEmptyState(
              title: 'No food/exposure logs yet',
              subtitle: 'Add foods, environments, or activities that might correlate with symptoms.',
              icon: Icons.restaurant_outlined,
              action: FilledButton.icon(
                onPressed: () => _snack(context, 'Add food/exposure (wireframe).'),
                icon: const Icon(Icons.add),
                label: const Text('Add log'),
              ),
            )
          else
            ...foods.map((f) => _FoodCard(item: f, onLink: (food) => _openLinkSheet(context, food))),
          const SizedBox(height: AppTokens.lg),
        ],
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openLinkSheet(BuildContext context, FoodLog food) {
    final t = Theme.of(context).textTheme;
    final events = repo.timelineForProfile(profileId).take(6).toList();

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(AppTokens.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Link to symptom', style: t.titleMedium),
              const SizedBox(height: AppTokens.xs),
              Text('Pick a timeline entry to connect with this food log.', style: t.bodySmall),
              const SizedBox(height: AppTokens.md),
              if (events.isEmpty)
                Text('No recent timeline items found.', style: t.bodySmall)
              else
                ...events.map((e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.link),
                      title: Text(e.title),
                      subtitle: Text('${e.type.label} - ${formatShortDate(e.timestamp)} - ${formatTime(e.timestamp)}'),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Linked "${food.food}" to "${e.title}" (wireframe).')),
                        );
                      },
                    )),
              const SizedBox(height: AppTokens.sm),
            ],
          ),
        );
      },
    );
  }
}

class _FoodCard extends StatelessWidget {
  const _FoodCard({required this.item, required this.onLink});

  final FoodLog item;
  final void Function(FoodLog item) onLink;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(item.food, style: t.titleMedium)),
                Text(formatTime(item.timestamp), style: t.bodySmall),
              ],
            ),
            const SizedBox(height: AppTokens.xs),
            Text(formatShortDate(item.timestamp), style: t.bodySmall),
            if ((item.suspectedReaction ?? '').isNotEmpty) ...[
              const SizedBox(height: AppTokens.xs),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                  const SizedBox(width: AppTokens.xs),
                  Expanded(child: Text('Suspected reaction: ${item.suspectedReaction}', style: t.bodySmall)),
                ],
              ),
            ],
            if ((item.notes ?? '').isNotEmpty) ...[
              const SizedBox(height: AppTokens.xs),
              Text(item.notes!, style: t.bodySmall),
            ],
            const SizedBox(height: AppTokens.sm),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => onLink(item),
                  icon: const Icon(Icons.link),
                  label: const Text('Link to symptom'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Edit (wireframe)',
                  onPressed: () => ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Edit food log (wireframe).'))),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

