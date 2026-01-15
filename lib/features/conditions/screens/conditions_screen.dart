import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/components.dart';
import '../../../core/utils/format.dart';

class ConditionsScreen extends StatelessWidget {
  const ConditionsScreen({super.key, required this.repo, required this.profile});

  final MockRepo repo;
  final PersonProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final list = repo.conditionsForProfile(profile.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conditions'),
        actions: [
          IconButton(
            tooltip: 'Add condition (wireframe)',
            onPressed: () => _snack(context, 'Add condition (wireframe).'),
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
                  Text('Problem list', style: t.titleMedium),
                  const SizedBox(height: AppTokens.xs),
                  Text(
                    'Register ongoing and past conditions. Link diary events to conditions to build a complete medical history.',
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.md),
          if (list.isEmpty)
            InlineEmptyState(
              title: 'No conditions yet',
              subtitle: 'Add the first condition (e.g., eczema, allergies, asthma).',
              icon: Icons.list_alt_outlined,
              action: FilledButton.icon(
                onPressed: () => _snack(context, 'Add condition (wireframe).'),
                icon: const Icon(Icons.add),
                label: const Text('Add condition'),
              ),
            )
          else
            ...list.map((c) => _ConditionCard(condition: c)),
          const SizedBox(height: AppTokens.lg),
        ],
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _ConditionCard extends StatelessWidget {
  const _ConditionCard({required this.condition});

  final Condition condition;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final status = switch (condition.status) {
      ConditionStatus.active => const StatusChip(label: 'Active', icon: Icons.circle, color: AppColors.success),
      ConditionStatus.monitoring => const StatusChip(label: 'Monitoring', icon: Icons.visibility, color: AppColors.warning),
      ConditionStatus.resolved => const StatusChip(label: 'Resolved', icon: Icons.check_circle, color: AppColors.textSecondary),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(condition.name, style: t.titleMedium)),
                status,
              ],
            ),
            const SizedBox(height: AppTokens.xs),
            if (condition.onset != null)
              Text('Onset: ${formatShortDate(condition.onset!)}', style: t.bodySmall),
            if ((condition.notes ?? '').isNotEmpty) ...[
              const SizedBox(height: AppTokens.xs),
              Text(condition.notes!, style: t.bodySmall),
            ],
            if (condition.tags.isNotEmpty) ...[
              const SizedBox(height: AppTokens.sm),
              Wrap(
                spacing: AppTokens.xs,
                runSpacing: AppTokens.xs,
                children: condition.tags
                    .map((x) => Chip(label: Text(x), visualDensity: VisualDensity.compact))
                    .toList(),
              ),
            ],
            const SizedBox(height: AppTokens.sm),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('View linked events (wireframe).'))),
                  icon: const Icon(Icons.timeline),
                  label: const Text('Linked events'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Edit (wireframe)',
                  onPressed: () => ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Edit condition (wireframe).'))),
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

