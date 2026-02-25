import 'package:flutter/material.dart';
import 'app.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';

import 'package:provider/provider.dart';
import 'core/providers/upload_provider.dart';
import 'core/services/background_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await initializeBackgroundService(); // Init Service Config. This is awaited because specific config is needed.
  
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // Don't block app startup on notification init - but run AFTER Supabase is ready
  NotificationService.init().then((_) => debugPrint('NotificationService init success')).catchError((e) => debugPrint('NotificationService init error: $e'));

  // Initialize Deep Link Listener for Auth Redirects
  AuthService.listenAuthRedirect();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UploadProvider()),
      ],
      child: const JourniApp(),
    ),
  );
}
