import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_shell.dart';
import 'core/supabase/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/mock_repo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase (replaces Firebase)
  try {
    await SupabaseConfig.initialize();
    print('✅ Supabase initialized successfully');
    print('   URL: ${SupabaseConfig.supabaseUrl}');
  } catch (e) {
    // Supabase initialization failed - app cannot work without it
    print('❌ Supabase initialization failed: $e');
    print('   Please check your Supabase configuration');
    print('   App authentication and storage will not work');
  }

  runApp(ProviderScope(child: MyApp(repo: MockRepo.bootstrap())));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.repo});

  final MockRepo repo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PV Reporting',
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
