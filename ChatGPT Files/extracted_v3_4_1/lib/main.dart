import 'package:flutter/material.dart';

import 'app/app_shell.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/mock_repo.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp(repo: MockRepo.bootstrap()));
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
