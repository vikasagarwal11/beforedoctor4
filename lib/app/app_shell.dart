import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../data/models/models.dart';
import '../data/repositories/mock_repo.dart';
import '../features/home/screens/home_screen.dart';
import '../features/insights/screens/insights_screen.dart';
import '../features/library/screens/library_screen.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/voice/screens/voice_live_screen_v2.dart';
import 'app_state.dart';

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
  StreamSubscription<User?>? _authSub;
  String _firebaseIdToken = '';

  @override
  void initState() {
    super.initState();
    _activeProfile = widget.repo.profiles.first;
    // Initialize auth asynchronously to ensure Firebase is ready
    Future.microtask(() => _listenForAuthToken());
  }

  void _setProfile(PersonProfile p) => setState(() => _activeProfile = p);

  void _listenForAuthToken() {
    // Production-grade: Use Firebase Auth with anonymous sign-in
    // If Firebase is not initialized, app will fail gracefully (no mock tokens in production)
    if (Firebase.apps.isEmpty) {
      // Firebase not configured - this should not happen in production
      print('❌ Firebase not initialized - authentication required');
      print('   Please ensure GoogleService-Info.plist is in ios/Runner/');
      _firebaseIdToken =
          ''; // Empty token - gateway will reject (as expected in production)
      return;
    }

    final auth = FirebaseAuth.instance;

    // Listen for auth token changes (set up BEFORE sign-in to catch all events)
    _authSub = FirebaseAuth.instance.idTokenChanges().listen((user) async {
      if (user == null) {
        // No user signed in - sign in anonymously
        print('! No Firebase user - attempting anonymous sign-in...');
        try {
          await auth.signInAnonymously();
          print('✅ Firebase anonymous sign-in successful');
          // Token will be fetched in the next listener event
        } catch (e) {
          print('❌ Failed to sign in anonymously: $e');
        }
        return;
      }

      // User is signed in - get fresh token
      print('🔑 Firebase user detected: ${user.uid}');
      try {
        final token = await user.getIdToken(true); // Force refresh
        if (!mounted) return;
        if (token != null) {
          setState(() {
            _firebaseIdToken = token;
          });
          print('✅ Firebase ID token obtained (length: ${token.length})');
        } else {
          print('⚠️ Firebase ID token is null');
          if (mounted) {
            setState(() {
              _firebaseIdToken = ''; // Empty token - gateway will reject
            });
          }
        }
      } catch (error) {
        print('❌ Failed to get Firebase ID token: $error');
        if (mounted) {
          setState(() {
            _firebaseIdToken = ''; // Empty token - gateway will reject
          });
        }
      }
    }, onError: (error) {
      print('❌ Firebase auth listener error: $error');
      if (mounted) {
        setState(() {
          _firebaseIdToken = ''; // Empty token - gateway will reject
        });
      }
    });

    // If user is already signed in (e.g., from previous app run), trigger listener manually
    if (auth.currentUser != null) {
      print('📱 Existing Firebase user found: ${auth.currentUser!.uid}');
      // Force trigger the listener by refreshing the token
      auth.currentUser!.getIdToken(true).then((token) {
        if (token != null && mounted) {
          setState(() {
            _firebaseIdToken = token;
          });
          print('✅ Firebase ID token loaded (length: ${token.length})');
        }
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: _state,
      child: AppStateBuilder(builder: (context, state) {
        final mq = MediaQuery.of(context);

        // Gateway URL
        // Use local gateway. Recommended for Android device testing: use `adb reverse tcp:8080 tcp:8080`
        const useLocalGateway = true; // Use local gateway
        final gatewayUrl = useLocalGateway
            ? 'ws://127.0.0.1:8080'
            : 'wss://beforedoctor-gateway-531178459822.us-central1.run.app';

        // Allow real gateway even with mock token for development
        // Set to false to force real audio (requires gateway server running)
        final useMockGateway =
            false; // Set to true for UI testing without gateway

        final pages = [
          HomeScreen(
              repo: widget.repo,
              activeProfile: _activeProfile,
              onProfileChange: _setProfile),
          // Use VoiceLiveScreenV2 (new Gemini Live-style UI)
          VoiceLiveScreenV2(
            gatewayUrl: Uri.parse(gatewayUrl),
            // For development, the gateway accepts mock tokens, but production requires real auth.
            firebaseIdToken: _firebaseIdToken, // Use state variable directly
            sessionConfig: {
              'patient_ref': _activeProfile.id,
              'reporter_ref': _activeProfile.id,
              'locale': 'en-US',
              'language_code': 'en-US',
              'system_instruction': {
                'text':
                    'You are a helpful clinical assistant for adverse event reporting.',
              },
            },
            useMockGateway:
                useMockGateway, // Use mock gateway when running with a mock token
          ),
          LibraryScreen(repo: widget.repo, profile: _activeProfile),
          InsightsScreen(repo: widget.repo, profile: _activeProfile),
          ProfileScreen(repo: widget.repo, profile: _activeProfile),
        ];

        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(state.textScale)),
          child: Theme(
            data: Theme.of(context).copyWith(
              visualDensity:
                  state.dense ? VisualDensity.compact : VisualDensity.standard,
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
