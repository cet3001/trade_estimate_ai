import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/services/supabase_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _supabaseService = SupabaseService();
  bool _isLoading = false;
  bool _handlingSignIn = false;
  StreamSubscription<AuthState>? _authSubscription;

  // Cached from route arguments; populated once in didChangeDependencies.
  bool _welcomeBack = false;
  bool _welcomeBackInitialized = false;

  @override
  void initState() {
    super.initState();
    _listenToAuthChanges();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_welcomeBackInitialized) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      _welcomeBack = args?['welcomeBack'] == true;
      _welcomeBackInitialized = true;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _listenToAuthChanges() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) async {
        final event = data.event;
        // Only handle signedIn when the user has actively initiated a sign-in
        // (_isLoading is true). Background session restores also emit
        // signedIn and must not trigger navigation from this screen.
        if (event == AuthChangeEvent.signedIn && _isLoading) {
          await _handleSignedIn();
        }
      },
      onError: (error) {
        if (mounted) {
          _showError('Authentication error: $error');
          setState(() => _isLoading = false);
        }
      },
    );
  }

  Future<void> _handleSignedIn() async {
    // Re-entrancy guard: prevents a second concurrent call racing if two
    // signedIn events arrive in quick succession.
    if (_handlingSignIn || !mounted) return;
    _handlingSignIn = true;

    try {
      setState(() => _isLoading = true);

      // Check if profile exists; create a minimal one if not
      final profile = await _supabaseService.getProfile();
      if (profile == null) {
        final user = _supabaseService.currentUser;
        await _supabaseService.createProfile(
          fullName: user?.userMetadata?['full_name'] as String? ?? '',
          companyName: '',
          email: user?.email ?? '',
        );
      }

      // Check onboarding status
      final onboardingDone = await _supabaseService.hasCompletedOnboarding();

      if (!mounted) return;
      if (onboardingDone) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to load profile. Please try again.');
        setState(() => _isLoading = false);
      }
    } finally {
      _handlingSignIn = false;
    }
  }

  Future<void> _signInWithApple() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      await _supabaseService.signInWithApple();
      // Auth state listener handles the rest after redirect
    } catch (e) {
      if (mounted) {
        _showError('Sign in failed. Please try again.');
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.negative,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(AppSpacing.lg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(),

                  // App icon / logo placeholder
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.borderDefault,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.construction_rounded,
                        size: 40,
                        color: AppColors.positive,
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xxxl),

                  // App name
                  Text(
                    'Trade Estimate AI',
                    style: AppTextStyles.heading1,
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: AppSpacing.xxxl),

                  // Subtext — differs based on welcome back mode
                  Text(
                    _welcomeBack
                        ? 'Welcome back. Sign in to continue.'
                        : 'Professional estimates for tradespeople.',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(),

                  // Sign in with Apple button
                  _SignInWithAppleButton(
                    onPressed: _isLoading ? null : _signInWithApple,
                  ),

                  const SizedBox(height: AppSpacing.huge),
                ],
              ),
            ),
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: AppColors.loadingOverlay,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.positive),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// TODO: Replace with sign_in_with_apple package before App Store submission.
// Icons.apple is not the official Apple logo and may cause App Store rejection.
// See: https://pub.dev/packages/sign_in_with_apple
class _SignInWithAppleButton extends StatelessWidget {
  const _SignInWithAppleButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.appleSignInBackground,
          foregroundColor: AppColors.appleSignInForeground,
          disabledBackgroundColor: AppColors.appleSignInBackground.withAlpha(137),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Apple logo — using a styled icon as placeholder
            const Icon(
              Icons.apple,
              size: 22,
              color: AppColors.appleSignInForeground,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Sign in with Apple',
              style: AppTextStyles.body.copyWith(
                color: AppColors.appleSignInForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
