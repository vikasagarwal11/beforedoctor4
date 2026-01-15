import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';

class AEReportPreviewScreen extends StatefulWidget {
  const AEReportPreviewScreen({
    super.key,
    required this.profileName,
    required this.suspectedProduct,
    required this.eventSummary,
    required this.narrative,
  });

  final String profileName;
  final String suspectedProduct;
  final String eventSummary;
  final String narrative;

  @override
  State<AEReportPreviewScreen> createState() => _AEReportPreviewScreenState();
}

class _AEReportPreviewScreenState extends State<AEReportPreviewScreen> {
  bool _deIdentified = true;
  bool _shareWithManufacturer = true;
  bool _shareWithRegulator = false;
  bool _shareWithClinician = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AE report preview'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.lg),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ICSR-style summary (wireframe)', style: t.titleMedium),
                  const SizedBox(height: AppTokens.xs),
                  Text(
                    'This is a draft preview. In production, the system would generate a structured adverse event report after collecting required fields and user confirmation.',
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: AppTokens.lg),
                  _kv('Reporter', 'Patient/Parent (app user)'),
                  _kv('Patient profile', widget.profileName),
                  _kv('Suspected product', widget.suspectedProduct),
                  _kv('Adverse event', widget.eventSummary),
                  _kv('Outcome', 'Unknown (not collected)'),
                  _kv('Seriousness', 'Non-serious (default wireframe)'),
                  _kv('Time to onset', 'Unknown (not collected)'),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Narrative', style: t.titleMedium),
                  const SizedBox(height: AppTokens.sm),
                  Text(widget.narrative.isEmpty ? '—' : widget.narrative),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Privacy & routing', style: t.titleMedium),
                  const SizedBox(height: AppTokens.sm),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _deIdentified,
                    onChanged: (v) => setState(() => _deIdentified = v),
                    title: const Text('De-identify before sharing'),
                    subtitle: const Text('Remove direct identifiers; keep clinical context.'),
                  ),
                  const Divider(height: AppTokens.lg),
                  CheckboxListTile(
                    value: _shareWithManufacturer,
                    onChanged: (v) => setState(() => _shareWithManufacturer = v ?? true),
                    title: const Text('Share with manufacturer'),
                    subtitle: const Text('Partner PV inbox (webhook / safety intake).'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: _shareWithRegulator,
                    onChanged: (v) => setState(() => _shareWithRegulator = v ?? false),
                    title: const Text('Share with regulator'),
                    subtitle: const Text('e.g., MedWatch / Yellow Card (if integrated).'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: _shareWithClinician,
                    onChanged: (v) => setState(() => _shareWithClinician = v ?? false),
                    title: const Text('Share with clinician'),
                    subtitle: const Text('Send to doctor inbox / export for visit.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.lg),
          ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Submitted (wireframe).')),
              );
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.send_outlined),
            label: const Text('Submit report'),
          ),
          const SizedBox(height: AppTokens.sm),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(k)),
          const SizedBox(width: AppTokens.sm),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

