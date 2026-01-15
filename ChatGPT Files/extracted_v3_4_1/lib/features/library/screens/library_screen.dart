import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../shared/widgets/components.dart';
import '../../conditions/screens/conditions_screen.dart';
import '../../medications/screens/medications_screen.dart';
import '../../food/screens/food_exposures_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.repo, required this.profile});

  final MockRepo repo;
  final PersonProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.lg),
        children: [
          Text('Everything that is not “voice now” lives here.', style: t.bodySmall),
          const SizedBox(height: AppTokens.md),
          _NavCard(
            icon: Icons.list_alt_outlined,
            title: 'Conditions',
            subtitle: 'All diagnoses, allergies, baseline context.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ConditionsScreen(repo: repo, profile: profile)),
            ),
          ),
          const SizedBox(height: AppTokens.sm),
          _NavCard(
            icon: Icons.medication_outlined,
            title: 'Medications & remedies',
            subtitle: 'Prescriptions, OTC, supplements, home remedies.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MedicationsScreen(repo: repo, profile: profile)),
            ),
          ),
          const SizedBox(height: AppTokens.sm),
          _NavCard(
            icon: Icons.restaurant_outlined,
            title: 'Food & triggers',
            subtitle: 'Track exposures and suspected triggers.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => FoodExposuresScreen(repo: repo, profile: profile)),
            ),
          ),
          const SizedBox(height: AppTokens.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Doctor visit report (next)', style: t.titleMedium),
                  const SizedBox(height: AppTokens.xs),
                  Text(
                    'In V3.4 we add a report preview screen and export UI. This section will link to it.',
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
