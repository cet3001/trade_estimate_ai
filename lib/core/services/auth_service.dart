import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Handles ONLY authentication. All other data concerns (profiles, estimates,
/// credits, etc.) remain in [SupabaseService].
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _supabase = Supabase.instance.client;
  final _googleSignIn = GoogleSignIn(scopes: ['email']);

  // ── Streams / current state ─────────────────────────────────────────────

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
  Session? get currentSession => _supabase.auth.currentSession;
  User? get currentUser => _supabase.auth.currentUser;

  // ── Apple ───────────────────────────────────────────────────────────────

  /// Launches the Apple OAuth flow via Supabase. The deep-link callback
  /// (`tradeestimateai://auth/callback`) triggers an [AuthChangeEvent.signedIn]
  /// which the caller should listen for to complete navigation.
  ///
  /// Note: [ensureProfileExists] is NOT called here because Apple goes through
  /// an OAuth redirect; profile creation is deferred to the auth state listener.
  Future<void> signInWithApple() async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: 'tradeestimateai://auth/callback',
    );
  }

  // ── Google ──────────────────────────────────────────────────────────────

  /// Signs in with Google using native sign-in, then exchanges the ID token
  /// with Supabase. Calls [ensureProfileExists] after a successful sign-in.
  Future<void> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('Google sign in cancelled');

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) throw Exception('No ID token from Google');

    await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );

    await ensureProfileExists();
  }

  // ── Email / Password ─────────────────────────────────────────────────────

  /// Signs in an existing user with email and password.
  /// Calls [ensureProfileExists] after a successful sign-in.
  Future<void> signInWithEmail(String email, String password) async {
    await _supabase.auth.signInWithPassword(email: email, password: password);
    await ensureProfileExists();
  }

  /// Creates a new user account with email and password.
  /// Calls [ensureProfileExists] after a successful sign-up.
  Future<void> signUpWithEmail(String email, String password) async {
    await _supabase.auth.signUp(email: email, password: password);
    await ensureProfileExists();
  }

  /// Sends a password-reset email with a deep-link redirect back to the app.
  Future<void> sendPasswordResetEmail(String email) async {
    await _supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: 'tradeestimateai://auth/reset',
    );
  }

  // ── Profile bootstrap ────────────────────────────────────────────────────

  /// Ensures a minimal profile row exists for the current user. Safe to call
  /// multiple times — uses upsert with `ignoreDuplicates: true` so existing
  /// rows are never overwritten. Only called after Google / Email auth; Apple
  /// goes through a redirect and its profile creation is handled by the auth
  /// state listener in the UI layer (which calls SupabaseService.createProfile
  /// with full onboarding data).
  Future<void> ensureProfileExists() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    await _supabase.from('profiles').upsert({
      'id': user.id,
      'email': user.email,
      'credits_remaining': 3,
      'created_at': DateTime.now().toIso8601String(),
    }, onConflict: 'id', ignoreDuplicates: true);
  }

  // ── Sign out ─────────────────────────────────────────────────────────────

  /// Signs out from both Google (if signed in) and Supabase.
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _supabase.auth.signOut();
  }
}
