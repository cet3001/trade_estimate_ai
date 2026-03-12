import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Auth Screen
// ─────────────────────────────────────────────────────────────────────────────

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _authService = AuthService();
  final _supabaseService = SupabaseService();

  // Per-button loading states
  bool _isLoadingApple = false;
  bool _isLoadingEmail = false;

  // Re-entrancy guard for the signedIn handler
  bool _handlingSignIn = false;

  // Email form visibility
  bool _emailFormVisible = false;

  // Email form mode: false = sign in, true = sign up
  bool _isSignUpMode = false;

  // Email form controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Password visibility toggles
  bool _passwordObscured = true;
  bool _confirmPasswordObscured = true;

  // Inline error message
  String? _errorMessage;

  // Auth state subscription
  StreamSubscription<AuthState>? _authSubscription;

  // Route args
  bool _welcomeBack = false;
  bool _welcomeBackInitialized = false;

  bool get _isAnyLoading => _isLoadingApple || _isLoadingEmail;

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
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ── Auth state listener ──────────────────────────────────────────────────

  void _listenToAuthChanges() {
    _authSubscription = _authService.authStateChanges.listen(
      (data) async {
        final event = data.event;
        // Handle sign-in regardless of loading state — background session
        // restores are filtered by the _handlingSignIn re-entrancy guard
        // inside _handleSignedIn. Removing the _isAnyLoading guard here
        // ensures Apple OAuth redirects are handled even after _isLoadingApple
        // is cleared in the finally block (Fix 1).
        if (event == AuthChangeEvent.signedIn) {
          await _handleSignedIn();
        }
      },
      onError: (error) {
        if (mounted) {
          _setError('Authentication error. Please try again.');
          setState(() {
            _isLoadingApple = false;
            _isLoadingEmail = false;
          });
        }
      },
    );
  }

  Future<void> _handleSignedIn() async {
    if (_handlingSignIn || !mounted) return;
    _handlingSignIn = true;

    try {
      // Check if profile exists; create a minimal one if not.
      final profile = await _supabaseService.getProfile();
      if (profile == null) {
        final user = _authService.currentUser;
        await _supabaseService.createProfile(
          fullName: user?.userMetadata?['full_name'] as String? ?? '',
          companyName: '',
          email: user?.email ?? '',
        );
      }

      // Check onboarding status.
      final onboardingDone = await _supabaseService.hasCompletedOnboarding();

      if (!mounted) return;
      if (onboardingDone) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
    } catch (e) {
      if (mounted) {
        _setError('Failed to load profile. Please try again.');
        setState(() {
          _isLoadingApple = false;
          _isLoadingEmail = false;
        });
      }
    } finally {
      _handlingSignIn = false;
      if (mounted) {
        setState(() {
          _isLoadingApple = false;
          _isLoadingEmail = false;
        });
      }
    }
  }

  // ── Sign in handlers ─────────────────────────────────────────────────────

  Future<void> _signInWithApple() async {
    if (_isAnyLoading) return;
    _clearError();
    setState(() => _isLoadingApple = true);
    try {
      await _authService.signInWithApple();
      // Auth state listener handles navigation after OAuth redirect.
    } catch (e) {
      if (mounted) {
        _setError(_friendlyError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isLoadingApple = false);
    }
  }

  Future<void> _submitEmailForm() async {
    if (_isAnyLoading) return;
    _clearError();

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _setError('Please enter your email and password.');
      return;
    }

    if (_isSignUpMode) {
      if (password != _confirmPasswordController.text) {
        _setError('Passwords do not match.');
        return;
      }
      if (password.length < 8) {
        _setError('Password must be at least 8 characters.');
        return;
      }
    }

    setState(() => _isLoadingEmail = true);
    try {
      if (_isSignUpMode) {
        await _authService.signUpWithEmail(email, password);
      } else {
        await _authService.signInWithEmail(email, password);
      }
      // Auth state listener handles navigation.
    } catch (e) {
      if (mounted) {
        _setError(_friendlyError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isLoadingEmail = false);
    }
  }

  // ── Forgot password bottom sheet ─────────────────────────────────────────

  void _showForgotPasswordSheet() {
    final resetEmailController =
        TextEditingController(text: _emailController.text.trim());
    bool isSending = false;
    bool sent = false;
    String? sheetError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xxxl,
                AppSpacing.xxl,
                AppSpacing.xxxl,
                AppSpacing.xxxl + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderDefault,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  Text('Reset Password', style: AppTextStyles.heading2),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Enter your email and we\'ll send you a reset link.',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  if (sent) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          color: AppColors.positive,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Reset email sent. Check your inbox.',
                            style: AppTextStyles.body.copyWith(
                              color: AppColors.positive,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    SizedBox(
                      width: double.infinity,
                      height: AppSpacing.buttonHeight,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.borderDefault),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.md),
                          ),
                        ),
                        child: const Text('Done'),
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: resetEmailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: AppTextStyles.body,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@example.com',
                        prefixIcon: const Icon(
                          Icons.email_outlined,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                      ),
                    ),

                    if (sheetError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        sheetError!,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.negative,
                        ),
                      ),
                    ],

                    const SizedBox(height: AppSpacing.xl),
                    SizedBox(
                      width: double.infinity,
                      height: AppSpacing.buttonHeight,
                      child: ElevatedButton(
                        onPressed: isSending
                            ? null
                            : () async {
                                final email =
                                    resetEmailController.text.trim();
                                if (email.isEmpty) {
                                  setSheetState(
                                    () => sheetError = 'Please enter your email.',
                                  );
                                  return;
                                }
                                setSheetState(() {
                                  isSending = true;
                                  sheetError = null;
                                });
                                try {
                                  await _authService
                                      .sendPasswordResetEmail(email);
                                  setSheetState(() {
                                    isSending = false;
                                    sent = true;
                                  });
                                } catch (e) {
                                  setSheetState(() {
                                    isSending = false;
                                    sheetError =
                                        'Could not send reset email. Try again.';
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.positive,
                          foregroundColor: AppColors.background,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.md),
                          ),
                          elevation: 0,
                        ),
                        child: isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.background,
                                  ),
                                ),
                              )
                            : Text(
                                'Send Reset Email',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.background,
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(resetEmailController.dispose);
  }

  // ── Error helpers ────────────────────────────────────────────────────────

  void _setError(String message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  void _clearError() {
    if (_errorMessage != null && mounted) setState(() => _errorMessage = null);
  }

  /// Maps Supabase / exception error strings to user-friendly messages.
  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('wrong-password') ||
        lower.contains('invalid-login-credentials') ||
        lower.contains('invalid login credentials') ||
        lower.contains('invalid_credentials')) {
      return 'Incorrect email or password.';
    }
    if (lower.contains('email-already-in-use') ||
        lower.contains('user-already-registered') ||
        lower.contains('user already registered')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (lower.contains('weak-password') || lower.contains('weak password')) {
      return 'Password must be at least 8 characters.';
    }
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('connection')) {
      return 'Check your internet connection and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: AppSpacing.huge),

                  // ── Logo ─────────────────────────────────────────────────
                  ClipOval(
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 140,
                      height: 140,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // ── Tagline ──────────────────────────────────────────────
                  Text(
                    _welcomeBack
                        ? 'Welcome back. Sign in to continue.'
                        : 'Instant estimates for trade professionals.',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(),

                  // ── Apple Sign In ────────────────────────────────────────
                  _AuthButton(
                    onPressed: _isAnyLoading ? null : _signInWithApple,
                    isLoading: _isLoadingApple,
                    backgroundColor: AppColors.appleSignInBackground,
                    foregroundColor: AppColors.appleSignInForeground,
                    disabledOpacity: _isAnyLoading && !_isLoadingApple,
                    icon: const Icon(
                      Icons.apple,
                      size: 22,
                      color: AppColors.appleSignInForeground,
                    ),
                    label: 'Continue with Apple',
                    labelStyle: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.appleSignInForeground,
                    ),
                    loaderColor: AppColors.appleSignInForeground,
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // ── Email button ─────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: AppSpacing.buttonHeight,
                    child: Opacity(
                      opacity: (_isAnyLoading && !_isLoadingEmail) ? 0.4 : 1.0,
                      child: OutlinedButton(
                        onPressed: (_isAnyLoading && !_isLoadingEmail)
                            ? null
                            : () {
                                _clearError();
                                setState(
                                  () => _emailFormVisible = !_emailFormVisible,
                                );
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(
                            color: AppColors.borderDefault,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.md),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.email_outlined,
                              size: 20,
                              color: AppColors.textPrimary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              'Continue with Email',
                              style: AppTextStyles.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Animated email form ──────────────────────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: _emailFormVisible
                        ? _EmailForm(
                            emailController: _emailController,
                            passwordController: _passwordController,
                            confirmPasswordController:
                                _confirmPasswordController,
                            passwordObscured: _passwordObscured,
                            confirmPasswordObscured: _confirmPasswordObscured,
                            isSignUpMode: _isSignUpMode,
                            isLoading: _isLoadingEmail,
                            isDisabled: _isAnyLoading && !_isLoadingEmail,
                            onTogglePasswordVisibility: () => setState(
                              () => _passwordObscured = !_passwordObscured,
                            ),
                            onToggleConfirmPasswordVisibility: () => setState(
                              () => _confirmPasswordObscured =
                                  !_confirmPasswordObscured,
                            ),
                            onToggleMode: () {
                              _clearError();
                              setState(() => _isSignUpMode = !_isSignUpMode);
                            },
                            onSubmit: _submitEmailForm,
                            onForgotPassword: _showForgotPasswordSheet,
                          )
                        : const SizedBox.shrink(),
                  ),

                  // ── Inline error message ─────────────────────────────────
                  if (_errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.negative.withAlpha(26),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.negative.withAlpha(77),
                        ),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.negative,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.xl),

                  // ── Legal footer ─────────────────────────────────────────
                  Text(
                    'By continuing, you agree to our Terms & Privacy Policy',
                    style: AppTextStyles.caption,
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable full-width auth button (Apple)
// ─────────────────────────────────────────────────────────────────────────────

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.onPressed,
    required this.isLoading,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.disabledOpacity,
    required this.icon,
    required this.label,
    required this.labelStyle,
    required this.loaderColor,
  });

  final VoidCallback? onPressed;
  final bool isLoading;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool disabledOpacity;
  final Widget icon;
  final String label;
  final TextStyle labelStyle;
  final Color loaderColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppSpacing.buttonHeight,
      child: Opacity(
        opacity: disabledOpacity ? 0.4 : 1.0,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            disabledBackgroundColor: backgroundColor.withAlpha(137),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.md),
            ),
          ),
          child: isLoading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(loaderColor),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    icon,
                    const SizedBox(width: AppSpacing.sm),
                    Text(label, style: labelStyle),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Email form (animated)
// ─────────────────────────────────────────────────────────────────────────────

class _EmailForm extends StatelessWidget {
  const _EmailForm({
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.passwordObscured,
    required this.confirmPasswordObscured,
    required this.isSignUpMode,
    required this.isLoading,
    required this.isDisabled,
    required this.onTogglePasswordVisibility,
    required this.onToggleConfirmPasswordVisibility,
    required this.onToggleMode,
    required this.onSubmit,
    required this.onForgotPassword,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool passwordObscured;
  final bool confirmPasswordObscured;
  final bool isSignUpMode;
  final bool isLoading;
  final bool isDisabled;
  final VoidCallback onTogglePasswordVisibility;
  final VoidCallback onToggleConfirmPasswordVisibility;
  final VoidCallback onToggleMode;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),

        // ── Sign In / Sign Up tabs ─────────────────────────────────────
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _ModeTab(
                label: 'Sign In',
                isSelected: !isSignUpMode,
                onTap: isSignUpMode ? onToggleMode : null,
              ),
              _ModeTab(
                label: 'Create Account',
                isSelected: isSignUpMode,
                onTap: !isSignUpMode ? onToggleMode : null,
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.xl),

        // ── Email field ───────────────────────────────────────────────
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          enabled: !isDisabled && !isLoading,
          style: AppTextStyles.body,
          decoration: InputDecoration(
            labelText: 'Email',
            hintText: 'you@example.com',
            prefixIcon: const Icon(
              Icons.email_outlined,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // ── Password field ────────────────────────────────────────────
        TextField(
          controller: passwordController,
          obscureText: passwordObscured,
          textInputAction:
              isSignUpMode ? TextInputAction.next : TextInputAction.done,
          onSubmitted: isSignUpMode ? null : (_) => onSubmit(),
          enabled: !isDisabled && !isLoading,
          style: AppTextStyles.body,
          decoration: InputDecoration(
            labelText: 'Password',
            hintText: isSignUpMode ? 'At least 8 characters' : '••••••••',
            prefixIcon: const Icon(
              Icons.lock_outline_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                passwordObscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.textSecondary,
                size: 20,
              ),
              onPressed: onTogglePasswordVisibility,
            ),
          ),
        ),

        // ── Forgot password (sign in mode only) ───────────────────────
        if (!isSignUpMode) ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isLoading ? null : onForgotPassword,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Forgot Password?',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
        ],

        // ── Confirm password (sign up mode only) ──────────────────────
        if (isSignUpMode) ...[
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: confirmPasswordController,
            obscureText: confirmPasswordObscured,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            enabled: !isDisabled && !isLoading,
            style: AppTextStyles.body,
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              hintText: '••••••••',
              prefixIcon: const Icon(
                Icons.lock_outline_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  confirmPasswordObscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                onPressed: onToggleConfirmPasswordVisibility,
              ),
            ),
          ),
        ],

        const SizedBox(height: AppSpacing.xl),

        // ── Submit button ─────────────────────────────────────────────
        SizedBox(
          height: AppSpacing.buttonHeight,
          child: ElevatedButton(
            onPressed: (isLoading || isDisabled) ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.positive,
              foregroundColor: AppColors.background,
              disabledBackgroundColor: AppColors.positive.withAlpha(100),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.md),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.background,
                      ),
                    ),
                  )
                : Text(
                    isSignUpMode ? 'Create Account' : 'Sign In',
                    style: AppTextStyles.bodyBold.copyWith(
                      color: AppColors.background,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sign In / Sign Up mode tab
// ─────────────────────────────────────────────────────────────────────────────

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surfaceElevated : AppColors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTextStyles.label.copyWith(
              color: isSelected
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
