import 'dart:io';

import 'package:flutter/material.dart';

import '../features/library/screens/library_screen.dart';

import '../features/voice/screens/voice_screen.dart';
import '../features/voice/screens/voice_live_screen.dart';

import 'app_state.dart';

import '../data/repositories/mock_repo.dart';
import '../data/models/models.dart';
import '../features/home/screens/home_screen.dart';
import '../features/insights/screens/insights_screen.dart';
import '../features/profile/screens/profile_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.repo});

  final MockRepo repo;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final AppState _state = AppState();
  int _tab = 1;
  late PersonProfile _activeProfile;

  @override
  void initState() {
    super.initState();
    _activeProfile = widget.repo.profiles.first;
  }

  void _setProfile(PersonProfile p) => setState(() => _activeProfile = p);

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: _state,
      child: AppStateBuilder(builder: (context, state) {
        final mq = MediaQuery.of(context);
        final firebaseIdToken = 'mock_token_for_testing'; // Replace with real Firebase token in production
        
        // Determine gateway URL based on platform
        // - Physical iOS device: Use Mac's IP (192.168.5.10 - update if your IP changes)
        // - Simulator: Use localhost
        // - Android emulator: Use 10.0.2.2
        final gatewayUrl = Platform.isAndroid
            ? 'ws://10.0.2.2:8080'
            : 'ws://192.168.5.10:8080'; // Your Mac's IP for physical device (localhost for simulator)
        
        // Allow real gateway even with mock token for development
        // Set to false to force real audio (requires gateway server running)
        final useMockGateway = false; // Set to true for UI testing without gateway
        
        final pages = [
        HomeScreen(repo: widget.repo, activeProfile: _activeProfile, onProfileChange: _setProfile),
        // Use VoiceLiveScreen (new Gemini Live-style UI) instead of VoiceScreen (old Teddy Buddy UI)
        VoiceLiveScreen(
          gatewayUrl: Uri.parse(gatewayUrl),
          // TODO: Replace with real Firebase authentication token from your auth service
          // Example: firebaseIdToken: FirebaseAuth.instance.currentUser?.getIdToken() ?? '',
          // For development, the gateway accepts mock tokens, but production requires real auth.
          firebaseIdToken: firebaseIdToken,
          sessionConfig: {
            'patient_ref': _activeProfile.id,
            'reporter_ref': _activeProfile.id,
            'locale': 'en-US',
            'language_code': 'en-US',
            'system_instruction': {
              'text': 'You are a helpful clinical assistant for adverse event reporting.',
            },
          },
          useMockGateway: useMockGateway, // Use mock gateway when running with a mock token
        ),
        LibraryScreen(repo: widget.repo, profile: _activeProfile),
        InsightsScreen(repo: widget.repo, profile: _activeProfile),
        ProfileScreen(repo: widget.repo, profile: _activeProfile),
      ];

        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(state.textScale)),
          child: Theme(
            data: Theme.of(context).copyWith(
              visualDensity: state.dense ? VisualDensity.compact : VisualDensity.standard,
            ),
            child: Scaffold(
              body: SafeArea(child: pages[_tab]),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.timeline_outlined),
                  selectedIcon: Icon(Icons.timeline),
                  label: 'Timeline',
                ),
                NavigationDestination(
                  icon: Icon(Icons.mic_none),
                  selectedIcon: Icon(Icons.mic),
                  label: 'Voice',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights),
                  label: 'Insights',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
            ),
          ),
        );
      }),
    );
  }
}
