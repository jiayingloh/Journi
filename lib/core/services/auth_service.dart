import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:app_links/app_links.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:async';
import 'dart:io' show Platform;
import '../config/supabase_config.dart';
import '../utils/logger.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Sign Up with Email and Password
  /// Also creates a record in the public 'users' table
  Future<void> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final AuthResponse res = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'name': name}, // Store name in metadata as backup
      );

      // Trigger 'handle_new_user' handles profile creation automatically
    } catch (e) {
      AppLogger.log('Sign Up Error: $e');
      rethrow;
    }
  }

  /// Sign In with Email and Password
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      AppLogger.log('Sign In Error: $e');
      rethrow;
    }
  }

  /// Sign Out
  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
      await _client.auth.signOut();
    } catch (e) {
      AppLogger.log('Sign Out Error: $e');
      rethrow;
    }
  }

  /// Sign In with Google (Native)
  /// Requires 'google_sign_in' package configuration
    Future<void> signInWithGoogle() async {
    try {
      // Setup Google Sign In
      // For Android, ensure you've added the SHA-1 fingerprint in the Firebase/Google Cloud Console.
      // For iOS, ensure you've added the reversed client ID to your URL schemes.
      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: Platform.isIOS ? SupabaseConfig.googleIosClientId : null,
        serverClientId: SupabaseConfig.googleWebClientId,
      );

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw 'Google Sign In Aborted by User';
      }

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null) {
        throw 'No Access Token found.';
      }

      if (idToken == null) {
        throw 'No ID Token found.';
      }

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } catch (e) {
      AppLogger.log('Google Sign In Error: $e');
      rethrow;
    }
  }




  static StreamSubscription? _sub;

  static void listenAuthRedirect() {
    final _appLinks = AppLinks();
    _sub = _appLinks.uriLinkStream.listen((Uri uri) async {
      try {
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
        AppLogger.log('Session refreshed from deep link: $uri');
      } catch (e) {
        AppLogger.log('Deep Link Auth Error: $e');
      }
    }, onError: (err) {
      AppLogger.log('Deep Link Stream Error: $err');
    });
  }
}
