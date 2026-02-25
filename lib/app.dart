import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/login_page.dart';

import 'features/home/main_scaffold.dart';
import 'features/media/global_upload_indicator.dart';

import 'core/config/theme.dart';

class JourniApp extends StatefulWidget {
  const JourniApp({super.key});

  static JourniAppState of(BuildContext context) =>
      context.findAncestorStateOfType<JourniAppState>()!;

  @override
  State<JourniApp> createState() => JourniAppState();
}

class JourniAppState extends State<JourniApp> {
  // Default to system, but we will allow toggling
  ThemeMode _themeMode = ThemeMode.system;

  void toggleTheme(bool isDark) {
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  ThemeMode get themeMode => _themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Journi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      // Listen to Auth State changes to determine where to go
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Hero(
                      tag: 'app_logo',
                      child: Image.asset('assets/images/logo_noBackground.png', width: 100),
                    ),
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(),
                  ],
                ),
              ),
            );
          }
          
          final session = snapshot.data?.session;
          if (session != null) {
            return const MainScaffold();
          } else {
            return const LoginPage();
          }
        },
      ),
      builder: (context, child) {
        return Stack(
          children: [
             if (child != null) child,
             const GlobalUploadIndicator(),
          ],
        );
      },
    );
  }
}
