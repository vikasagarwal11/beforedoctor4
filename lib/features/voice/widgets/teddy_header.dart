import 'package:flutter/material.dart';
import '../../../app/app_state.dart';
import 'health_buddy_header.dart';

class TeddyHeader extends StatelessWidget {
  const TeddyHeader({
    super.key,
  });

  void _openSettings(BuildContext context, AppState appState) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Voice Character Style',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFD81B60),
                    ),
              ),
              const SizedBox(height: 20),
              RadioListTile<VoiceCharacterStyle>(
                title: const Row(
                  children: [
                    Text('🐻 Teddy Bear'),
                    SizedBox(width: 8),
                    Text('(Warm, nurturing)'),
                  ],
                ),
                subtitle: const Text(
                  'Maximum emotional warmth with pink palette',
                  style: TextStyle(fontSize: 12),
                ),
                value: VoiceCharacterStyle.teddyBear,
                groupValue: appState.voiceCharacterStyle,
                onChanged: (value) {
                  if (value != null) {
                    appState.setVoiceCharacterStyle(value);
                    Navigator.pop(context);
                  }
                },
                activeColor: const Color(0xFFEC407A),
              ),
              RadioListTile<VoiceCharacterStyle>(
                title: const Row(
                  children: [
                    Text('😊 Friendly Character'),
                    SizedBox(width: 8),
                    Text('(Modern, clean)'),
                  ],
                ),
                subtitle: const Text(
                  'Modern blue character with mint gradient',
                  style: TextStyle(fontSize: 12),
                ),
                value: VoiceCharacterStyle.friendlyCharacter,
                groupValue: appState.voiceCharacterStyle,
                onChanged: (value) {
                  if (value != null) {
                    appState.setVoiceCharacterStyle(value);
                    Navigator.pop(context);
                  }
                },
                activeColor: const Color(0xFF64B5F6),
              ),
              RadioListTile<VoiceCharacterStyle>(
                title: const Row(
                  children: [
                    Text('💚 Health Buddy'),
                    SizedBox(width: 8),
                    Text('(Simple, minimal)'),
                  ],
                ),
                subtitle: const Text(
                  'Clean design with green/yellow gradient',
                  style: TextStyle(fontSize: 12),
                ),
                value: VoiceCharacterStyle.healthBuddy,
                groupValue: appState.voiceCharacterStyle,
                onChanged: (value) {
                  if (value != null) {
                    appState.setVoiceCharacterStyle(value);
                    Navigator.pop(context);
                  }
                },
                activeColor: const Color(0xFF66BB6A),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppStateBuilder(
      builder: (context, appState) {
        final style = appState.voiceCharacterStyle;
        final isTeddyBear = style == VoiceCharacterStyle.teddyBear;
        final isHealthBuddy = style == VoiceCharacterStyle.healthBuddy;
        
        // Use Health Buddy header for that style
        if (isHealthBuddy) {
          return HealthBuddyHeader(
            onSettingsTap: () => _openSettings(context, appState),
          );
        }
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isTeddyBear ? Icons.favorite : Icons.mic,
                    color: isTeddyBear ? const Color(0xFFEC407A) : const Color(0xFF64B5F6),
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isTeddyBear ? 'Teddy Buddy' : 'Voice Assistant',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: isTeddyBear ? const Color(0xFFD81B60) : const Color(0xFF1976D2),
                    ),
                  ),
                ],
              ),
              // Settings button - highly visible with white background
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openSettings(context, appState),
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        Icons.settings,
                        color: isTeddyBear ? const Color(0xFFEC407A) : const Color(0xFF64B5F6),
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

