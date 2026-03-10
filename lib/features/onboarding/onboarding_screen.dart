import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/services/supabase_service.dart';

// ---------------------------------------------------------------------------
// Internal page enum — drives which page is visible.
// ---------------------------------------------------------------------------

enum _OnboardingPage { businessInfo, ready }

// ---------------------------------------------------------------------------
// OnboardingScreen — single StatefulWidget managing both pages.
// ---------------------------------------------------------------------------

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  _OnboardingPage _currentPage = _OnboardingPage.businessInfo;

  void _showReadyPage() {
    setState(() => _currentPage = _OnboardingPage.ready);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: switch (_currentPage) {
        _OnboardingPage.businessInfo => _BusinessInfoPage(
            onSuccess: _showReadyPage,
          ),
        _OnboardingPage.ready => const _ReadyPage(),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 2 — Business Info
// ---------------------------------------------------------------------------

class _BusinessInfoPage extends StatefulWidget {
  const _BusinessInfoPage({required this.onSuccess});

  final VoidCallback onSuccess;

  @override
  State<_BusinessInfoPage> createState() => _BusinessInfoPageState();
}

class _BusinessInfoPageState extends State<_BusinessInfoPage> {
  final _formKey = GlobalKey<FormBuilderState>();
  final _supabaseService = SupabaseService();
  bool _isLoading = false;

  // Pre-fill email from the authenticated user (Apple already provided it).
  String get _prefillEmail =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  Future<void> _onContinue() async {
    if (_isLoading) return;

    final form = _formKey.currentState;
    if (form == null || !form.saveAndValidate()) return;

    final values = form.value;
    final fullName = (values['full_name'] as String).trim();
    final companyName = (values['company_name'] as String).trim();
    final email = (values['email'] as String).trim();
    final phone = (values['phone'] as String?)?.trim();
    final licenseNumber = (values['license_number'] as String?)?.trim();

    setState(() => _isLoading = true);

    try {
      // Issue 1 fix: use createProfile (upsert) instead of updateProfile
      // (update). For a first-launch user the profile row may not yet have
      // all fields populated; update() would throw via .single() on a
      // non-existent row whereas upsert() handles both insert and update.
      await _supabaseService.createProfile(
        fullName: fullName,
        companyName: companyName,
        email: email,
        phone: phone?.isEmpty ?? true ? null : phone,
        licenseNumber:
            licenseNumber?.isEmpty ?? true ? null : licenseNumber,
      );

      if (!mounted) return;
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save profile. Please try again.',
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
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.xxxl),

            // Title
            Text('Your Business', style: AppTextStyles.heading1),

            const SizedBox(height: AppSpacing.sm),

            // Subtitle
            Text(
              'This info appears on every estimate.',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: AppSpacing.xxxl),

            // Form — expands to fill available space above the button
            Expanded(
              child: SingleChildScrollView(
                child: FormBuilder(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Full name — required
                      FormBuilderTextField(
                        name: 'full_name',
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                        ),
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(
                            errorText: 'Full name is required.',
                          ),
                        ]),
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      // Company name — required
                      FormBuilderTextField(
                        name: 'company_name',
                        decoration: const InputDecoration(
                          labelText: 'Company Name',
                        ),
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(
                            errorText: 'Company name is required.',
                          ),
                        ]),
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      // Email — required + email format, pre-filled
                      FormBuilderTextField(
                        name: 'email',
                        initialValue: _prefillEmail,
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(
                            errorText: 'Email is required.',
                          ),
                          FormBuilderValidators.email(
                            errorText: 'Enter a valid email address.',
                          ),
                        ]),
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      // Phone — optional
                      FormBuilderTextField(
                        name: 'phone',
                        decoration: const InputDecoration(
                          labelText: 'Phone Number (optional)',
                        ),
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      // License number — optional
                      FormBuilderTextField(
                        name: 'license_number',
                        decoration: const InputDecoration(
                          labelText: 'License Number (optional)',
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _onContinue(),
                      ),

                      // Bottom padding so the last field clears the keyboard
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
            ),

            // Continue button — full width, pinned to bottom
            const SizedBox(height: AppSpacing.lg),
            _OnboardingCtaButton(
              label: 'Continue',
              onPressed: _isLoading ? null : _onContinue,
              isLoading: _isLoading,
            ),

            const SizedBox(height: AppSpacing.huge),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 3 — Ready
// ---------------------------------------------------------------------------

class _ReadyPage extends StatefulWidget {
  const _ReadyPage();

  @override
  State<_ReadyPage> createState() => _ReadyPageState();
}

class _ReadyPageState extends State<_ReadyPage>
    with SingleTickerProviderStateMixin {
  // Issue 3 fix: store SupabaseService as a field instead of instantiating
  // it inline inside the async method on every call.
  final _supabaseService = SupabaseService();

  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    // Start animation on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onCreateFirstEstimate() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      await _supabaseService.setOnboardingComplete();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      if (!mounted) return;
      // Even if persisting the flag fails, proceed to home so the user
      // isn't stuck. The router will re-check on next cold launch.
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Spacer(),

            // Animated checkmark — scales from 0 → 1 over 400 ms
            ScaleTransition(
              scale: _scaleAnimation,
              child: const Icon(
                Icons.check_circle_rounded,
                size: 80,
                color: AppColors.positive,
              ),
            ),

            const SizedBox(height: AppSpacing.xxxl),

            // Heading
            Text(
              "You're ready to write estimates.",
              style: AppTextStyles.heading1,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: AppSpacing.lg),

            // Subtext
            Text(
              'Tap below to create your first estimate.',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),

            const Spacer(),

            // CTA button
            _OnboardingCtaButton(
              label: 'Create Your First Estimate',
              onPressed: _isLoading ? null : _onCreateFirstEstimate,
              isLoading: _isLoading,
            ),

            const SizedBox(height: AppSpacing.huge),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Issue 4 fix: shared CTA button helper — eliminates the duplicated
// ElevatedButton builds that existed in both _BusinessInfoPage and
// _ReadyPage.
// ---------------------------------------------------------------------------

class _OnboardingCtaButton extends StatelessWidget {
  const _OnboardingCtaButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppSpacing.buttonHeight, // Issue 2 fix: named constant
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.positive,
          foregroundColor: AppColors.textPrimary,
          disabledBackgroundColor: AppColors.positive.withAlpha(100),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.textPrimary,
                  ),
                ),
              )
            : Text(
                label,
                style: AppTextStyles.heading2.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
      ),
    );
  }
}
