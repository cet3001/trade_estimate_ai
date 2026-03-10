import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/models/entitlements.dart';
import '../../core/services/iap_service.dart';
import '../../core/services/supabase_service.dart';
import '../../widgets/loading_overlay.dart';

// ---------------------------------------------------------------------------
// PaywallScreen
// ---------------------------------------------------------------------------

class PaywallScreen extends StatefulWidget {
  /// Called after a successful purchase so the caller can trigger a state
  /// refresh. If null, the screen simply pops after success.
  final VoidCallback? onSuccess;

  const PaywallScreen({super.key, this.onSuccess});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _iap = IapService();
  final _service = SupabaseService();

  // Which option last reported an error (null = none).
  // Values: 'subscription' | 'credits5' | 'credits15' | 'restore'
  String? _errorSource;

  // Whether we are currently restoring purchases (separate flag because
  // IapService.purchasePending is shared with buy flows).
  bool _restoring = false;

  // Prevent re-entrant dismiss when the listener fires multiple times.
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _iap.addListener(_onIapChanged);
    // Clear any stale error from a previous session.
    _iap.clearError();
  }

  @override
  void dispose() {
    _iap.removeListener(_onIapChanged);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // IapService listener — detect purchase success and auto-pop.
  // ---------------------------------------------------------------------------

  void _onIapChanged() {
    // Only act when a pending operation has just completed with no error.
    if (!_iap.purchasePending && _iap.lastError == null && !_dismissing) {
      _checkAndDismissIfSuccessful();
    }
    if (mounted) setState(() {});
  }

  Future<void> _checkAndDismissIfSuccessful() async {
    if (_dismissing) return;
    _dismissing = true;

    // Fetch fresh entitlements from Supabase.
    final profile = await _service.getProfile();
    if (!mounted) {
      _dismissing = false;
      return;
    }
    if (profile == null) {
      _dismissing = false;
      return;
    }

    final entitlements = Entitlements.fromUserProfile(profile);
    if (entitlements.canGenerateEstimate) {
      widget.onSuccess?.call();
      Navigator.of(context).pop();
    } else {
      _dismissing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Purchase actions
  // ---------------------------------------------------------------------------

  Future<void> _buySubscription() async {
    setState(() => _errorSource = null);
    _iap.clearError();
    final ok = await _iap.buySubscription();
    if (!ok && mounted) {
      setState(() => _errorSource = 'subscription');
    }
  }

  Future<void> _buyCredits5() async {
    setState(() => _errorSource = null);
    _iap.clearError();
    final ok = await _iap.buyCredits(5);
    if (!ok && mounted) {
      setState(() => _errorSource = 'credits5');
    }
  }

  Future<void> _buyCredits15() async {
    setState(() => _errorSource = null);
    _iap.clearError();
    final ok = await _iap.buyCredits(15);
    if (!ok && mounted) {
      setState(() => _errorSource = 'credits15');
    }
  }

  Future<void> _restorePurchases() async {
    setState(() {
      _errorSource = null;
      _restoring = true;
    });
    _iap.clearError();

    await _iap.restorePurchases();

    // Wait for the stream to settle (IapService has its own 5-second fallback).
    // We poll once after a short delay here; the listener handles auto-pop.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final profile = await _service.getProfile();
    if (!mounted) return;

    setState(() => _restoring = false);

    if (profile != null) {
      final entitlements = Entitlements.fromUserProfile(profile);
      if (entitlements.canGenerateEstimate) {
        widget.onSuccess?.call();
        Navigator.of(context).pop();
        return;
      }
    }

    if (_iap.lastError != null) {
      setState(() => _errorSource = 'restore');
    } else {
      // No error but no entitlement either — tell user nothing was found.
      setState(() => _errorSource = 'restore');
    }
  }

  // ---------------------------------------------------------------------------
  // Price helpers — use real App Store price when available, else fallback.
  // ---------------------------------------------------------------------------

  String _price(String productId, String fallback) {
    final product = _iap.getProduct(productId);
    return product?.price ?? fallback;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pending = _iap.purchasePending || _restoring;

    return LoadingOverlay(
      isLoading: pending,
      message: 'Processing...',
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: AppColors.textPrimary, size: AppSpacing.lg),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // -- Hero heading
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: Text(
                    'Trade Estimate AI Pro',
                    style: AppTextStyles.heading1,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: Text(
                    'Professional estimates in 2 minutes.',
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // -- Subscription card
                _buildSubscriptionCard(),
                const SizedBox(height: AppSpacing.xxl),

                // -- OR divider
                Center(
                  child: Text(
                    'OR buy credits:',
                    style: AppTextStyles.label
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // -- Credit pack cards (side by side)
                Row(
                  children: [
                    Expanded(child: _buildCredits5Card()),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: _buildCredits15Card()),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),

                // -- Restore Purchases
                _buildRestoreButton(),
                const SizedBox(height: AppSpacing.lg),

                // -- Apple legal text
                Text(
                  'Payment will be charged to your Apple ID account at the '
                  'confirmation of purchase. Subscription automatically renews '
                  'unless it is cancelled at least 24 hours before the end of '
                  'the current period.',
                  style: AppTextStyles.caption,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Subscription card
  // ---------------------------------------------------------------------------

  Widget _buildSubscriptionCard() {
    final price = _price(IapService.kSubscriptionMonthly, r'$39.99');
    final error = _errorSource == 'subscription' ? _iap.lastError : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: AppColors.positive.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // MOST POPULAR badge
          Text(
            'MOST POPULAR',
            style: AppTextStyles.label.copyWith(
              color: AppColors.positive,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Monthly Subscription', style: AppTextStyles.heading2),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$price / month',
            style: AppTextStyles.body
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Unlimited estimates',
            style: AppTextStyles.body
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Subscribe button
          SizedBox(
            width: double.infinity,
            height: AppSpacing.buttonHeight,
            child: ElevatedButton(
              onPressed: _iap.purchasePending ? null : _buySubscription,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.positive,
                foregroundColor: AppColors.textPrimary,
                disabledBackgroundColor:
                    AppColors.positive.withValues(alpha: 0.4),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.md),
                ),
              ),
              child: Text(
                'Subscribe',
                style: AppTextStyles.heading2
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
          ),

          // Inline error
          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildInlineError(error),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Credits 5 card
  // ---------------------------------------------------------------------------

  Widget _buildCredits5Card() {
    final price = _price(IapService.kCredits5, r'$9.99');
    final error = _errorSource == 'credits5' ? _iap.lastError : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('5 Estimates', style: AppTextStyles.heading2),
          const SizedBox(height: AppSpacing.xs),
          Text(
            price,
            style: AppTextStyles.body
                .copyWith(color: AppColors.positive),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Best for\noccasional use',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            height: AppSpacing.buttonHeight,
            child: ElevatedButton(
              onPressed: _iap.purchasePending ? null : _buyCredits5,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surfaceOverlay,
                foregroundColor: AppColors.textPrimary,
                disabledBackgroundColor:
                    AppColors.surfaceOverlay.withValues(alpha: 0.4),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.md),
                ),
              ),
              child: Text('Buy', style: AppTextStyles.body),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildInlineError(error),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Credits 15 card
  // ---------------------------------------------------------------------------

  Widget _buildCredits15Card() {
    final price = _price(IapService.kCredits15, r'$19.99');
    final error = _errorSource == 'credits15' ? _iap.lastError : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('15 Estimates', style: AppTextStyles.heading2),
          const SizedBox(height: AppSpacing.xs),
          Text(
            price,
            style: AppTextStyles.body
                .copyWith(color: AppColors.positive),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Best value',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            height: AppSpacing.buttonHeight,
            child: ElevatedButton(
              onPressed: _iap.purchasePending ? null : _buyCredits15,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surfaceOverlay,
                foregroundColor: AppColors.textPrimary,
                disabledBackgroundColor:
                    AppColors.surfaceOverlay.withValues(alpha: 0.4),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.md),
                ),
              ),
              child: Text('Buy', style: AppTextStyles.body),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildInlineError(error),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Restore purchases
  // ---------------------------------------------------------------------------

  Widget _buildRestoreButton() {
    final restoreError = _errorSource == 'restore'
        ? (_iap.lastError ?? 'No purchases found to restore.')
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
          child: TextButton(
            onPressed: (_iap.purchasePending || _restoring)
                ? null
                : _restorePurchases,
            child: Text(
              'Restore Purchases',
              style: AppTextStyles.body.copyWith(color: AppColors.accent),
            ),
          ),
        ),
        if (restoreError != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _buildInlineError(restoreError),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared inline error widget
  // ---------------------------------------------------------------------------

  Widget _buildInlineError(String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline,
          color: AppColors.negative,
          size: AppSpacing.lg,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            message,
            style:
                AppTextStyles.caption.copyWith(color: AppColors.negative),
          ),
        ),
      ],
    );
  }
}
