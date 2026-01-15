import 'package:flutter/material.dart';

import '../features/library/screens/library_screen.dart';

import '../features/voice/screens/voice_screen.dart';

import 'app_state.dart';

import '../data/repositories/mock_repo.dart';
import '../data/models/models.dart';
import '../features/home/screens/home_screen.dart';
import '../features/conditions/screens/conditions_screen.dart';
import '../features/medications/screens/medications_screen.dart';
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
        final pages = [
        HomeScreen(repo: widget.repo, activeProfile: _activeProfile, onProfileChange: _setProfile),
        VoiceScreen(repo: widget.repo, activeProfile: _activeProfile),
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
