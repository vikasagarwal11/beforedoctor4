// Supabase Configuration
// Production-grade: Connects Flutter app to Supabase backend
// Replaces Firebase authentication and storage

import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase configuration for the app
/// These values connect to your Supabase project
class SupabaseConfig {
  // Supabase URL from your Supabase dashboard
  static const String supabaseUrl = 'https://scrksfxnkxmvvdzwmqnc.supabase.co';

  // Anonymous key (safe to use in client apps)
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNjcmtzZnhua3htdnZkendtcW5jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM2MDM2NTcsImV4cCI6MjA3OTE3OTY1N30.tumWvHiXv7VsX0QTm-iyc5L0dwGFDTtgEkHAUieMcIY';

  // Storage bucket for audio files
  static const String audioStorageBucket = 'audio-files';

  /// Initialize Supabase
  /// Call this in main() before runApp()
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
        autoRefreshToken: true,
      ),
      storageOptions: const StorageClientOptions(
        retryAttempts: 3,
      ),
    );
  }
}

/// Global Supabase client instance
/// Access throughout the app using: supabase.auth, supabase.from(), etc.
SupabaseClient get supabase => Supabase.instance.client;
