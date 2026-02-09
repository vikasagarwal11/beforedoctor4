import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase/supabase_config.dart';
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
  StreamSubscription<AuthState>? _authSub;
  String _supabaseAccessToken = '';

  @override
  void initState() {
    super.initState();
    _activeProfile = widget.repo.profiles.first;
    // Initialize auth asynchronously to ensure Supabase is ready
    Future.microtask(() => _listenForAuthToken());
  }

  void _setProfile(PersonProfile p) => setState(() => _activeProfile = p);

  void _listenForAuthToken() {
    // Production-grade: Use Supabase Auth with anonymous sign-in
    // Replaces Firebase authentication

    // Listen for auth state changes
    _authSub = supabase.auth.onAuthStateChange.listen((data) async {
      final session = data.session;

      if (session == null) {
        // No user signed in - sign in anonymously with retry logic
        print('! No Supabase user - attempting anonymous sign-in...');
        int retryCount = 0;
        const maxRetries = 3;

        while (retryCount < maxRetries) {
          try {
            final response = await supabase.auth.signInAnonymously();
            print('✅ Supabase anonymous sign-in successful');
            print('   User ID: ${response.user?.id}');
            // Token will be available in the next auth state change event
            return;
          } catch (e) {
            retryCount++;
            print('❌ Sign-in attempt $retryCount failed: $e');

            if (retryCount < maxRetries) {
              // Wait before retrying (exponential backoff)
              await Future.delayed(Duration(seconds: retryCount * 2));
              print('   Retrying... ($retryCount/$maxRetries)');
            } else {
              print('❌ Max retries reached. Please check:');
              print('   1. Internet connection is working');
              print('   2. Supabase URL is correct');
              print(
                  '   3. Device can reach: https://scrksfxnkxmvvdzwmqnc.supabase.co');

              // Set empty token - gateway will use mock token in dev mode
              if (mounted) {
                setState(() {
                  _supabaseAccessToken = '';
                });
              }
            }
          }
        }
        return;
      }

      // User is signed in - get access token
      final accessToken = session.accessToken;
      print('🔑 Supabase user detected: ${session.user.id}');
      print('   Is anonymous: ${session.user.isAnonymous}');

      if (mounted) {
        setState(() {
          _supabaseAccessToken = accessToken;
        });
        print(
            '✅ Supabase access token obtained (length: ${accessToken.length})');
      }
    }, onError: (error) {
      print('❌ Supabase auth listener error: $error');
      if (mounted) {
        setState(() {
          _supabaseAccessToken = ''; // Empty token - gateway will reject
        });
      }
    });

    // If user is already signed in (e.g., from previous app run), get token immediately
    final currentSession = supabase.auth.currentSession;
    if (currentSession != null) {
      print('📱 Existing Supabase user found: ${currentSession.user.id}');
      setState(() {
        _supabaseAccessToken = currentSession.accessToken;
      });
      print(
          '✅ Supabase access token loaded (length: ${currentSession.accessToken.length})');
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

        // Backend selection
        // The app now uses Supabase (Edge Functions) as the backend for voice turns.
        // Gateway/WebSocket configuration is intentionally disabled in the frontend.
        const useMockGateway = false; // Set true for UI-only testing

        final pages = [
          HomeScreen(
              repo: widget.repo,
              activeProfile: _activeProfile,
              onProfileChange: _setProfile),
          // Use VoiceLiveScreenV2 (new Gemini Live-style UI)
          VoiceLiveScreenV2(
            // Kept for backward compatibility with the screen/controller signature.
            // Not used when SupabaseGatewayClient is active.
            gatewayUrl: Uri.parse('ws://unused.local'),
            // Use Supabase access token (replaces Firebase ID token)
            firebaseIdToken:
                _supabaseAccessToken, // Uses same parameter name for backward compatibility
            sessionConfig: {
              'patient_ref': _activeProfile.id,
              'reporter_ref': _activeProfile.id,
              'locale': 'en-US',
              'language_code': 'en-US',
              'system_instruction': {
                'text':
                    '''You are a clinical documentation assistant for a medical intake app.

Generate a structured doctor-style summary based strictly on the user's transcript.
Use these headings in order:
1) Chief Complaint
2) HPI (History of Present Illness)
3) Symptoms & Severity
4) Onset/Duration
5) Relevant Medications
6) Allergies
7) Past Medical History
8) Assessment (non-diagnostic)
9) Recommended Next Steps
10) Red Flags (if any)
11) Follow-up Questions (max 3, only if info is missing)

Rules:
- Do NOT provide a definitive diagnosis.
- Be concise and clinically appropriate.
- If severe or emergency symptoms are mentioned, advise immediate medical care.
- Respond ONLY in English.''',
              },
              'response_language': 'English',
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
