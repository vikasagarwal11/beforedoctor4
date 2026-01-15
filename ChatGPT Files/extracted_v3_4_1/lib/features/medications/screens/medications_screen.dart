import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/components.dart';
import '../../../core/utils/format.dart';

class MedicationsScreen extends StatelessWidget {
  const MedicationsScreen({super.key, required this.repo, required this.profile});

  final MockRepo repo;
  final PersonProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final meds = repo.medicationsForProfile(profile.id);
    final active = meds.where((m) => m.isActive).toList();
    final inactive = meds.where((m) => !m.isActive).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medications & remedies'),
        actions: [
          IconButton(
            tooltip: 'Add (wireframe)',
            onPressed: () => _snack(context, 'Add medication/remedy (wireframe).'),
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
                  Text('Registry', style: t.titleMedium),
                  const SizedBox(height: AppTokens.xs),
                  Text(
                    'Track prescriptions, OTC medicines, supplements, and home remedies. Log every dose as an event in the timeline.',
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.md),
          Text('Active', style: t.titleSmall),
          const SizedBox(height: AppTokens.sm),
          if (active.isEmpty)
            const InlineEmptyState(
              title: 'No active items',
              subtitle: 'Add a medication course or remedy to track dosing and reactions.',
              icon: Icons.medication_outlined,
            )
          else
            ...active.map((m) => _MedCard(item: m)),
          const SizedBox(height: AppTokens.lg),
          Text('History', style: t.titleSmall),
          const SizedBox(height: AppTokens.sm),
          if (inactive.isEmpty)
            const InlineEmptyState(
              title: 'No history yet',
              subtitle: 'Past courses and as-needed items will appear here.',
              icon: Icons.history,
            )
          else
            ...inactive.map((m) => _MedCard(item: m)),
          const SizedBox(height: AppTokens.lg),
        ],
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _MedCard extends StatelessWidget {
  const _MedCard({required this.item});

  final MedicationItem item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final typeLabel = switch (item.type) {
      MedicationType.prescription => 'Prescription',
      MedicationType.otc => 'OTC',
      MedicationType.supplement => 'Supplement',
      MedicationType.homeRemedy => 'Home remedy',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(item.name, style: t.titleMedium)),
                StatusChip(
                  label: typeLabel,
                  icon: Icons.local_pharmacy_outlined,
                  color: item.type == MedicationType.prescription ? AppColors.primary : AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: AppTokens.xs),
            if ((item.dose ?? '').isNotEmpty || (item.schedule ?? '').isNotEmpty)
              Text('${item.dose ?? ''} ${item.schedule ?? ''}'.trim(), style: t.bodySmall),
            if ((item.reason ?? '').isNotEmpty) ...[
              const SizedBox(height: AppTokens.xs),
              Text('Reason: ${item.reason}', style: t.bodySmall),
            ],
            const SizedBox(height: AppTokens.xs),
            if (item.startAt != null)
              Text(
                item.stopAt == null ? 'Started: ${formatShortDate(item.startAt!)}' : 'Course: ${formatShortDate(item.startAt!)} → ${formatShortDate(item.stopAt!)}',
                style: t.bodySmall,
              ),
            const SizedBox(height: AppTokens.sm),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Log dose (wireframe).'))),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Log dose'),
                ),
                const SizedBox(width: AppTokens.sm),
                OutlinedButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Link reactions (wireframe).'))),
                  icon: const Icon(Icons.link),
                  label: const Text('Link reactions'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

