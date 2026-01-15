import 'package:flutter/material.dart';

import '../../../core/constants/tokens.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/components.dart';

class CreateEpisodeScreen extends StatefulWidget {
  const CreateEpisodeScreen({super.key, required this.repo, required this.profile});

  final MockRepo repo;
  final PersonProfile profile;

  @override
  State<CreateEpisodeScreen> createState() => _CreateEpisodeScreenState();
}

class _CreateEpisodeScreenState extends State<CreateEpisodeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _productController = TextEditingController(text: '');
  String _type = 'Medication';

  bool _monitoringOn = true;
  bool _watchlistOn = true;

  bool _cloudSync = true;
  bool _shareClinician = false;
  bool _sharePV = false;

  @override
  void dispose() {
    _productController.dispose();
    super.dispose();
  }

  void _create() {
    if (!_formKey.currentState!.validate()) return;

    final e = Episode(
      id: 'e_${DateTime.now().millisecondsSinceEpoch}',
      profileId: widget.profile.id,
      productName: _productController.text.trim(),
      productType: _type,
      startAt: DateTime.now(),
      status: EpisodeStatus.active,
      monitoringOn: _monitoringOn,
      watchlistOn: _watchlistOn,
      shareClinicianDefault: _shareClinician,
      sharePVDefault: _sharePV,
    );

    widget.repo.episodes.insert(0, e);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Create episode')),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.md),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('For: ${widget.profile.displayName}', style: t.titleMedium),
                  const SizedBox(height: AppTokens.sm),
                  Text('This is a UI-only wireframe. No pharmacy/EHR integrations are enabled yet.', style: t.bodySmall),
                  const SizedBox(height: AppTokens.lg),
                  const SectionHeader(title: 'Product'),
                  const SizedBox(height: AppTokens.sm),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _productController,
                          decoration: const InputDecoration(
                            labelText: 'Medication or vaccine name',
                            hintText: 'e.g., Amoxicillin / MMR Vaccine',
                            prefixIcon: Icon(Icons.search),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Enter a product name';
                            return null;
                          },
                        ),
                        const SizedBox(height: AppTokens.md),
                        DropdownButtonFormField<String>(
                          value: _type,
                          decoration: const InputDecoration(
                            labelText: 'Type',
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Medication', child: Text('Medication')),
                            DropdownMenuItem(value: 'Vaccine', child: Text('Vaccine')),
                          ],
                          onChanged: (v) => setState(() => _type = v ?? _type),
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
                  const SectionHeader(title: 'Episode settings'),
                  const SizedBox(height: AppTokens.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Monitoring'),
                    subtitle: const Text('Smart check-ins during the exposure window'),
                    value: _monitoringOn,
                    onChanged: (v) => setState(() => _monitoringOn = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Safety watchlist'),
                    subtitle: const Text('Relevant updates and education for this product'),
                    value: _watchlistOn,
                    onChanged: (v) => setState(() => _watchlistOn = v),
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
                  const SectionHeader(title: 'Privacy & sharing (granular)'),
                  const SizedBox(height: AppTokens.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cloud sync'),
                    subtitle: const Text('Sync across devices (can be turned off)'),
                    value: _cloudSync,
                    onChanged: (v) => setState(() => _cloudSync = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Default: share clinician summary'),
                    subtitle: const Text('You control each share action'),
                    value: _shareClinician,
                    onChanged: (v) => setState(() => _shareClinician = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Default: de-identified PV sharing'),
                    subtitle: const Text('Opt-in; separate from clinician sharing'),
                    value: _sharePV,
                    onChanged: (v) => setState(() => _sharePV = v),
                  ),
                  const SizedBox(height: AppTokens.sm),
                  Text(
                    'Note: In production, consent changes create audit events. This wireframe only shows UI behavior.',
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.lg),
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.check),
            label: const Text('Create episode'),
          ),
          const SizedBox(height: AppTokens.lg),
        ],
      ),
    );
  }
}
