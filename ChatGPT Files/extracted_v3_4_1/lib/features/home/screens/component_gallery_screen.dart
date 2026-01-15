import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../shared/widgets/components.dart';
import '../../../shared/widgets/states.dart';

class ComponentGalleryScreen extends StatelessWidget {
  const ComponentGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Component gallery')),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.md),
        children: [
          Text('Buttons', style: t.titleMedium),
          const SizedBox(height: AppTokens.sm),
          Wrap(
            spacing: AppTokens.sm,
            runSpacing: AppTokens.sm,
            children: [
              FilledButton(onPressed: () {}, child: const Text('Filled')),
              OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
              TextButton(onPressed: () {}, child: const Text('Text')),
              FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.mic), label: const Text('With icon')),
            ],
          ),
          const SizedBox(height: AppTokens.lg),
          Text('Chips', style: t.titleMedium),
          const SizedBox(height: AppTokens.sm),
          Wrap(
            spacing: AppTokens.sm,
            runSpacing: AppTokens.sm,
            children: const [
              StatusChip(label: 'Monitoring on', icon: Icons.notifications_active, color: AppColors.success),
              StatusChip(label: 'Queued offline', icon: Icons.cloud_off, color: AppColors.textSecondary),
              StatusChip(label: 'PV share on', icon: Icons.shield_outlined, color: AppColors.warning),
            ],
          ),
          const SizedBox(height: AppTokens.lg),
          Text('States', style: t.titleMedium),
          const SizedBox(height: AppTokens.sm),
          const OfflineBanner(),
          InlineEmptyState(
            title: 'No events yet',
            subtitle: 'Log a symptom, reaction, or note to build the timeline.',
            icon: Icons.sick_outlined,
            action: FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.mic), label: const Text('Log event')),
          ),
          const SizedBox(height: AppTokens.md),
          InlineErrorState(
            title: 'Something went wrong',
            subtitle: 'This is a preview of an error state in production.',
            onRetry: () {},
          ),
          const SizedBox(height: AppTokens.md),
          Text('Skeleton', style: t.titleMedium),
          const SizedBox(height: AppTokens.sm),
          const Skeleton(height: 16),
          const SizedBox(height: AppTokens.sm),
          const Skeleton(height: 44, radius: AppTokens.rLg),
          const SizedBox(height: AppTokens.lg),
          Text('Waveform', style: t.titleMedium),
          const SizedBox(height: AppTokens.sm),
          const FakeWaveform(isActive: true),
          const SizedBox(height: AppTokens.lg),
        ],
      ),
    );
  }
}
