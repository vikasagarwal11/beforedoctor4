import 'package:flutter/material.dart';

import '../../../app/app_state.dart';
import '../../../core/constants/tokens.dart';
import '../../../data/repositories/mock_repo.dart';
import '../../../data/models/models.dart';
import '../../../shared/widgets/components.dart';
import '../../assistant/screens/voice_assistant_screen.dart';
import '../../home/screens/component_gallery_screen.dart';
import '../../privacy/screens/privacy_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.repo,
    required this.profile,
  });

  final MockRepo repo;
  final PersonProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(AppTokens.md),
      children: [
        Text('Profile', style: t.titleLarge),
        const SizedBox(height: AppTokens.xs),
        Text('Wireframe identity + family profiles + preferences.', style: t.bodySmall),
        const SizedBox(height: AppTokens.lg),
        Card(
          child: ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Privacy & sharing'),
            subtitle: const Text('Control clinician/PV sharing, exports, and consent (wireframe).'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PrivacyScreen()),
            ),
          ),
        ),
        const SizedBox(height: AppTokens.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.md, horizontal: AppTokens.lg),
            child: Row(
              children: [
                CircleAvatar(radius: 26, child: Text(profile.displayName.substring(0, 1))),
                const SizedBox(width: AppTokens.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.displayName, style: t.titleMedium),
                      const SizedBox(height: AppTokens.xs),
                      Text('${profile.type} • ${profile.ageLabel}', style: t.bodySmall),
                    ],
                  ),
                ),
                IconButton(onPressed: () => _snack(context, 'Edit profile (wireframe).'), icon: const Icon(Icons.edit_outlined)),
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
                const SectionHeader(title: 'Family profiles'),
                const SizedBox(height: AppTokens.sm),
                ...repo.profiles.map((p) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(child: Text(p.displayName.substring(0, 1))),
                      title: Text(p.displayName),
                      subtitle: Text('${p.type} • ${p.ageLabel}'),
                      trailing: p.id == profile.id ? const Icon(Icons.check_circle) : null,
                      onTap: () => _snack(context, 'Switch profile (wireframe).'),
                    )),
                const Divider(height: AppTokens.xl),
                FilledButton.icon(
                  onPressed: () => _snack(context, 'Add family member (wireframe).'),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add family member'),
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
                const SectionHeader(title: 'Voice & assistant'),
                const SizedBox(height: AppTokens.sm),
                Builder(
                  builder: (context) {
                    final appState = AppStateScope.of(context);
                    return Row(
                      children: [
                        const Icon(Icons.record_voice_over_outlined),
                        const SizedBox(width: AppTokens.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Voice tone'),
                              Text(appState.voiceTone.label, style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<VoiceTone>(
                            value: appState.voiceTone,
                            items: VoiceTone.values
                                .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) appState.setVoiceTone(v);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppTokens.sm),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mic),
                  title: const Text('Try voice diary'),
                  subtitle: const Text('Conversational capture and follow-ups (wireframe)'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VoiceAssistantScreen(repo: repo, profile: profile),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.language_outlined),
                  title: const Text('Language'),
                  subtitle: const Text('English'),
                  onTap: () => _snack(context, 'Language picker (wireframe).'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.security_outlined),
                  title: const Text('Biometrics'),
                  subtitle: const Text('Off'),
                  onTap: () => _snack(context, 'Biometrics flow (wireframe).'),
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
                const SectionHeader(title: 'Design system (wireframe)'),
                const SizedBox(height: AppTokens.sm),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.grid_view_outlined),
                  title: const Text('Component gallery'),
                  subtitle: const Text('All UI components + states in one place'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ComponentGalleryScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AppTokens.lg),
        OutlinedButton(
          onPressed: () => _snack(context, 'Sign out (wireframe).'),
          child: const Text('Sign out'),
        ),
      ],
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
