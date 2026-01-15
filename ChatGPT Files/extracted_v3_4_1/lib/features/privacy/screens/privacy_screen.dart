import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../app/app_state.dart';
import '../../../shared/widgets/components.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _localOnly = true;
  bool _clinicianShare = false;
  bool _pvShare = false;
  bool _analytics = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(AppTokens.md),
      children: [
        Text('Privacy', style: t.titleLarge),
        const SizedBox(height: AppTokens.xs),
        Text('Everything is opt-in. This screen defines the behavioral contract.', style: t.bodySmall),
        const SizedBox(height: AppTokens.lg),

        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Device & UI (wireframe)'),
                const SizedBox(height: AppTokens.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Simulate offline'),
                  subtitle: const Text('Forcing queued sync states across the app'),
                  value: AppStateScope.of(context).offline,
                  onChanged: (v) => setState(() => AppStateScope.of(context).setOffline(v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Compact density'),
                  subtitle: const Text('Tighter spacing for power users'),
                  value: AppStateScope.of(context).dense,
                  onChanged: (v) => setState(() => AppStateScope.of(context).setDense(v)),
                ),
                const SizedBox(height: AppTokens.sm),
                Text('Text scale', style: t.bodyLarge),
                Slider(
                  value: AppStateScope.of(context).textScale,
                  min: 0.85,
                  max: 1.15,
                  divisions: 6,
                  label: AppStateScope.of(context).textScale.toStringAsFixed(2),
                  onChanged: (v) => setState(() => AppStateScope.of(context).setTextScale(v)),
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
                const SectionHeader(title: 'Consent controls'),
                const SizedBox(height: AppTokens.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Local-only mode'),
                  subtitle: const Text('Disables sync and sharing'),
                  value: _localOnly,
                  onChanged: (v) => setState(() {
                    _localOnly = v;
                    if (_localOnly) {
                      _clinicianShare = false;
                      _pvShare = false;
                      _analytics = false;
                    }
                  }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Clinician sharing'),
                  subtitle: const Text('One-tap share summaries'),
                  value: _clinicianShare,
                  onChanged: _localOnly ? null : (v) => setState(() => _clinicianShare = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('De-identified PV sharing'),
                  subtitle: const Text('Share to regulators/pharma partners'),
                  value: _pvShare,
                  onChanged: _localOnly ? null : (v) => setState(() => _pvShare = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Product analytics'),
                  subtitle: const Text('Anonymous app quality telemetry'),
                  value: _analytics,
                  onChanged: _localOnly ? null : (v) => setState(() => _analytics = v),
                ),
                const SizedBox(height: AppTokens.md),
                Container(
                  padding: const EdgeInsets.all(AppTokens.md),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTokens.rMd),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: AppTokens.sm),
                      Expanded(
                        child: Text(
                          'In production: every consent change is versioned and auditable. This wireframe demonstrates behavior and states only.',
                          style: t.bodySmall,
                        ),
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
                const SectionHeader(title: 'Data rights (preview)'),
                const SizedBox(height: AppTokens.sm),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Export my data'),
                  subtitle: const Text('Generate a local export file (wireframe)'),
                  onTap: () => _snack(context, 'Export queued (wireframe).'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete my data'),
                  subtitle: const Text('Remove local data and cloud records (wireframe)'),
                  onTap: () => _snack(context, 'Delete flow (wireframe).'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
