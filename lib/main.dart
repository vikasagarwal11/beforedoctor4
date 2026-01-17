import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app/app_shell.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/mock_repo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase only if GoogleService-Info.plist exists
  // For now, we use mock tokens so Firebase is optional
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // Firebase not configured (missing GoogleService-Info.plist)
    // App will continue with mock tokens
    print('⚠️ Firebase initialization skipped: $e');
    print('   App will continue with mock token authentication');
  }
  
  runApp(ProviderScope(child: MyApp(repo: MockRepo.bootstrap())));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.repo});

  final MockRepo repo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PRO + PV Wireframe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(0.92),
          ),
          child: child!,
        );
      },
      home: AppShell(repo: repo),
    );
  }
}
