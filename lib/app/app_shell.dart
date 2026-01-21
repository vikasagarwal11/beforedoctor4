import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  StreamSubscription<User?>? _authSub;
  String _firebaseIdToken = '';

  @override
  void initState() {
    super.initState();
    _activeProfile = widget.repo.profiles.first;
    _listenForAuthToken();
  }

  void _setProfile(PersonProfile p) => setState(() => _activeProfile = p);

  void _listenForAuthToken() {
    // Production-grade: Use Firebase Auth with anonymous sign-in
    // If Firebase is not initialized, app will fail gracefully (no mock tokens in production)
    if (Firebase.apps.isEmpty) {
      // Firebase not configured - this should not happen in production
      print('❌ Firebase not initialized - authentication required');
      print('   Please ensure GoogleService-Info.plist is in ios/Runner/');
      _firebaseIdToken = ''; // Empty token - gateway will reject (as expected in production)
      return;
    }
    
    // Sign in anonymously if no user is signed in (production-grade approach)
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      // Sign in anonymously - this creates a Firebase user immediately
      auth.signInAnonymously().then((credential) {
        print('✅ Firebase anonymous sign-in successful');
        print('   User ID: ${credential.user?.uid}');
        // Token will be fetched via the listener below
      }).catchError((error) {
        print('❌ Firebase anonymous sign-in failed: $error');
        print('   Make sure Anonymous Auth is enabled in Firebase Console');
        if (mounted) {
          setState(() {
            _firebaseIdToken = ''; // Empty token - will cause gateway to reject
          });
        }
      });
    }
    
    // Listen for auth token changes (gets token when user signs in)
    _authSub = FirebaseAuth.instance.idTokenChanges().listen((user) async {
      if (user == null) {
        // No user signed in - this should not happen after anonymous sign-in
        print('⚠️ No Firebase user - attempting anonymous sign-in...');
        try {
          await auth.signInAnonymously();
          // Token will be fetched in the next listener event
        } catch (e) {
          print('❌ Failed to sign in anonymously: $e');
        }
        return;
      }
      
      // User is signed in - get fresh token
      try {
        final token = await user.getIdToken(true); // Force refresh
        if (!mounted) return;
        if (token != null) {
          setState(() {
            _firebaseIdToken = token;
            print('✅ Firebase ID token obtained (length: ${token.length})');
          });
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
        final firebaseIdToken = _firebaseIdToken;
        
        // Determine gateway URL based on platform
        // PRODUCTION: Use Cloud Run URL (no local network permission needed)
  // DEVELOPMENT: Using local gateway for testing transcription issue
  // final gatewayUrl = 'wss://beforedoctor-gateway-531178459822.us-central1.run.app'; // Production Cloud Run URL

  // Development URLs (for local testing - using this to debug transcription):
  final gatewayUrl = Platform.isAndroid
      ? 'ws://10.0.2.2:8080'
      : 'ws://192.168.5.10:8080'; // Mac's IP - network verified working!
        
        // Allow real gateway even with mock token for development
        // Set to false to force real audio (requires gateway server running)
        final useMockGateway = false; // Set to true for UI testing without gateway
        
        final pages = [
        HomeScreen(repo: widget.repo, activeProfile: _activeProfile, onProfileChange: _setProfile),
        // Use VoiceLiveScreen (new Gemini Live-style UI) instead of VoiceScreen (old Teddy Buddy UI)
        VoiceLiveScreen(
          gatewayUrl: Uri.parse(gatewayUrl),
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
