import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/constants/trade_templates.dart';
import '../../core/models/entitlements.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/supabase_service.dart';

// ---------------------------------------------------------------------------
// SettingsScreen
// ---------------------------------------------------------------------------

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = SupabaseService();
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameController = TextEditingController();
  final _labourRateController = TextEditingController();

  // State
  UserProfile? _profile;
  bool _loadingProfile = true;
  bool _savingProfile = false;
  bool _signingOut = false;
  bool _deletingAccount = false;
  String? _profileSaveError;
  bool _profileSaveSuccess = false;

  TradeType? _selectedTrade;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _labourRateController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _loadProfile() async {
    setState(() => _loadingProfile = true);
    try {
      final profile = await _service.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _nameController.text = profile?.fullName ?? '';
        final rate = profile?.defaultLaborRate;
        _labourRateController.text = rate != null ? rate.toStringAsFixed(2) : '';
        _selectedTrade = _tradeFromString(profile?.defaultTrade);
        _loadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingProfile = false);
    }
  }

  TradeType? _tradeFromString(String? value) {
    if (value == null) return null;
    try {
      return TradeType.values.firstWhere((t) => t.value == value);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Derived helpers
  // ---------------------------------------------------------------------------

  Entitlements get _entitlements {
    if (_profile == null) return Entitlements.empty;
    return Entitlements.fromUserProfile(_profile!);
  }

  // ---------------------------------------------------------------------------
  // Profile save
  // ---------------------------------------------------------------------------

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _savingProfile = true;
      _profileSaveError = null;
      _profileSaveSuccess = false;
    });

    try {
      final updates = <String, dynamic>{
        'full_name': _nameController.text.trim(),
      };

      final rateText = _labourRateController.text.trim();
      if (rateText.isNotEmpty) {
        final rate = double.tryParse(rateText);
        if (rate != null) updates['default_labor_rate'] = rate;
      } else {
        updates['default_labor_rate'] = null;
      }

      if (_selectedTrade != null) {
        updates['default_trade'] = _selectedTrade!.value;
      }

      final updated = await _service.updateProfile(updates);
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _savingProfile = false;
        _profileSaveSuccess = true;
        _profileSaveError = null;
      });

      // Auto-clear success message after 3 seconds.
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _profileSaveSuccess = false);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingProfile = false;
        _profileSaveError = 'Failed to save profile. Please try again.';
        _profileSaveSuccess = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Subscription management
  // ---------------------------------------------------------------------------

  Future<void> _openSubscriptionManagement() async {
    final uri = Uri.parse('https://apps.apple.com/account/subscriptions');
    final canLaunch = await canLaunchUrl(uri);
    if (!mounted) return;
    if (!canLaunch) {
      _showSnackError('Unable to open subscription settings. Please manage your subscription in the App Store app.');
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openPaywall() {
    Navigator.of(context).pushNamed('/paywall');
  }

  // ---------------------------------------------------------------------------
  // Sign out
  // ---------------------------------------------------------------------------

  Future<void> _signOut() async {
    final confirmed = await _showConfirmDialog(
      title: 'Sign Out',
      message: 'Are you sure you want to sign out?',
      confirmLabel: 'Sign Out',
      destructive: false,
    );
    if (!confirmed) return;

    setState(() => _signingOut = true);
    try {
      await _service.signOut();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (_) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _signingOut = false);
      _showSnackError('Sign out failed. Please try again.');
    }
  }

  // ---------------------------------------------------------------------------
  // Delete account
  // ---------------------------------------------------------------------------

  Future<void> _deleteAccount() async {
    // Step 1: Warn dialog.
    final proceed = await _showConfirmDialog(
      title: 'Delete Account',
      message:
          'This will permanently delete your account and all estimates. This cannot be undone.',
      confirmLabel: 'Continue',
      destructive: true,
    );
    if (!proceed || !mounted) return;

    // Step 2: Text-confirmation dialog — user must type "DELETE".
    final typed = await _showDeleteConfirmationDialog();
    if (typed != 'DELETE' || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await _service.deleteAccount();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingAccount = false);
      _showSnackError('Account deletion failed. Please try again.');
      return;
    }
    // RPC succeeded — best-effort sign out, always navigate to /auth.
    try {
      await _service.signOut();
    } catch (_) {
      // Session already invalidated server-side; ignore sign-out errors.
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth', (_) => false);
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required bool destructive,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(title, style: AppTextStyles.heading2),
        content: Text(
          message,
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.body.copyWith(color: AppColors.accent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              confirmLabel,
              style: AppTextStyles.body.copyWith(
                color: destructive ? AppColors.negative : AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Shows a dialog where the user must type "DELETE" to confirm.
  /// Returns the typed string, or null if cancelled.
  Future<String?> _showDeleteConfirmationDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surfaceElevated,
              title: Text(
                'Confirm Deletion',
                style: AppTextStyles.heading2.copyWith(color: AppColors.negative),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Type DELETE to confirm:',
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    autocorrect: false,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textPrimary,
                      letterSpacing: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'DELETE',
                      hintStyle: AppTextStyles.body
                          .copyWith(color: AppColors.textTertiary),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.md),
                        borderSide: const BorderSide(
                          color: AppColors.borderDefault,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.md),
                        borderSide: const BorderSide(
                          color: AppColors.negative,
                          width: 2,
                        ),
                      ),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: Text(
                    'Cancel',
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.accent),
                  ),
                ),
                TextButton(
                  onPressed: controller.text == 'DELETE'
                      ? () => Navigator.of(ctx).pop('DELETE')
                      : null,
                  child: Text(
                    'Delete My Account',
                    style: AppTextStyles.body.copyWith(
                      color: controller.text == 'DELETE'
                          ? AppColors.negative
                          : AppColors.textTertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return result;
  }

  void _showSnackError(String message) {
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
          borderRadius: BorderRadius.circular(AppSpacing.md),
        ),
        margin: const EdgeInsets.all(AppSpacing.lg),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final loading = _signingOut || _deletingAccount;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            title: Text('Settings', style: AppTextStyles.heading2),
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: AppColors.textPrimary,
                size: AppSpacing.lg,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: _loadingProfile
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.positive),
                  ),
                )
              : _buildContent(),
        ),

        // Full-screen overlay while signing out or deleting.
        if (loading)
          const Positioned.fill(
            child: _LoadingOverlay(
              message: 'Please wait...',
            ),
          ),
      ],
    );
  }

  Widget _buildContent() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        children: [
          _buildSectionHeader('PROFILE'),
          _buildProfileSection(),
          const SizedBox(height: AppSpacing.xxl),
          _buildSectionHeader('SUBSCRIPTION'),
          _buildSubscriptionSection(),
          const SizedBox(height: AppSpacing.xxl),
          _buildSectionHeader('ACCOUNT'),
          _buildAccountSection(),
          const SizedBox(height: AppSpacing.huge),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section header
  // ---------------------------------------------------------------------------

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Text(
        title,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 1.0,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section: Profile
  // ---------------------------------------------------------------------------

  Widget _buildProfileSection() {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // Full name
          _buildTextFieldTile(
            label: 'Full Name',
            controller: _nameController,
            hintText: 'Your name',
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Name is required';
              }
              return null;
            },
          ),
          _buildDivider(),

          // Email — read only
          _buildReadOnlyTile(
            label: 'Email',
            value: _profile?.email ?? _service.currentUser?.email ?? '—',
          ),
          _buildDivider(),

          // Default labour rate
          _buildTextFieldTile(
            label: 'Default Labour Rate',
            controller: _labourRateController,
            hintText: '0.00',
            prefixText: '\$ ',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            validator: (value) {
              if (value == null || value.trim().isEmpty) return null;
              final parsed = double.tryParse(value.trim());
              if (parsed == null || parsed < 0) {
                return 'Enter a valid rate';
              }
              return null;
            },
          ),
          _buildDivider(),

          // Trade selector
          _buildTradeDropdownTile(),
          _buildDivider(),

          // Save button + feedback
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: AppSpacing.buttonHeight,
                  child: ElevatedButton(
                    onPressed: _savingProfile ? null : _saveProfile,
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
                    child: _savingProfile
                        ? const SizedBox(
                            width: AppSpacing.lg,
                            height: AppSpacing.lg,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.textPrimary),
                            ),
                          )
                        : Text(
                            'Save Profile',
                            style: AppTextStyles.heading2
                                .copyWith(color: AppColors.textPrimary),
                          ),
                  ),
                ),

                // Inline success message
                if (_profileSaveSuccess) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _buildInlineSuccess('Profile saved successfully.'),
                ],

                // Inline error message
                if (_profileSaveError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _buildInlineError(_profileSaveError!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextFieldTile({
    required String label,
    required TextEditingController controller,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? prefixText,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.label.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            inputFormatters: inputFormatters,
            style: AppTextStyles.body,
            validator: validator,
            decoration: InputDecoration(
              hintText: hintText,
              prefixText: prefixText,
              prefixStyle:
                  AppTextStyles.body.copyWith(color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.surfaceElevated,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.md),
                borderSide:
                    const BorderSide(color: AppColors.borderDefault),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.md),
                borderSide:
                    const BorderSide(color: AppColors.borderDefault),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.md),
                borderSide: const BorderSide(
                  color: AppColors.borderActive,
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.md),
                borderSide: const BorderSide(color: AppColors.negative),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.md),
                borderSide:
                    const BorderSide(color: AppColors.negative, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyTile({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.body,
          ),
          Flexible(
            child: Text(
              value,
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTradeDropdownTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Default Trade',
            style:
                AppTextStyles.label.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<TradeType>(
            initialValue: _selectedTrade,
            dropdownColor: AppColors.surfaceElevated,
            style: AppTextStyles.body,
            iconEnabledColor: AppColors.textSecondary,
            hint: Text(
              'Select trade',
              style: AppTextStyles.body
                  .copyWith(color: AppColors.textTertiary),
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceElevated,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.md),
                borderSide:
                    const BorderSide(color: AppColors.borderDefault),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.md),
                borderSide:
                    const BorderSide(color: AppColors.borderDefault),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.md),
                borderSide: const BorderSide(
                  color: AppColors.borderActive,
                  width: 2,
                ),
              ),
            ),
            items: TradeType.values.map((trade) {
              final info = TradeTemplates.byType(trade);
              return DropdownMenuItem<TradeType>(
                value: trade,
                child: Row(
                  children: [
                    Text(info.emoji),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      info.label,
                      style: AppTextStyles.body,
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) => setState(() => _selectedTrade = value),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section: Subscription
  // ---------------------------------------------------------------------------

  Widget _buildSubscriptionSection() {
    final entitlements = _entitlements;
    final isSubscribed = entitlements.hasActiveSubscription;
    final credits = _profile?.creditsRemaining ?? 0;

    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // Status row
          ListTile(
            tileColor: AppColors.surface,
            title: Text('Subscription', style: AppTextStyles.body),
            trailing: _buildSubscriptionBadge(isSubscribed),
          ),
          _buildDivider(),

          // Credits row
          ListTile(
            tileColor: AppColors.surface,
            title: Text('Credits Remaining', style: AppTextStyles.body),
            trailing: Text(
              '$credits',
              style: AppTextStyles.body.copyWith(
                color: credits > 0 ? AppColors.positive : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _buildDivider(),

          // Action button
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: SizedBox(
              width: double.infinity,
              height: AppSpacing.buttonHeight,
              child: isSubscribed
                  ? ElevatedButton(
                      onPressed: _openSubscriptionManagement,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surfaceElevated,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                        side: const BorderSide(color: AppColors.borderDefault),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.md),
                        ),
                      ),
                      child: Text(
                        'Manage Subscription',
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.accent),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _openPaywall,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.positive,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.md),
                        ),
                      ),
                      child: Text(
                        'Upgrade to Pro',
                        style: AppTextStyles.heading2
                            .copyWith(color: AppColors.textPrimary),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionBadge(bool isSubscribed) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isSubscribed
            ? AppColors.positive.withValues(alpha: 0.15)
            : AppColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(
          color: isSubscribed ? AppColors.positive : AppColors.borderDefault,
        ),
      ),
      child: Text(
        isSubscribed ? 'Pro — Active' : 'Free Plan',
        style: AppTextStyles.label.copyWith(
          color: isSubscribed ? AppColors.positive : AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section: Account
  // ---------------------------------------------------------------------------

  Widget _buildAccountSection() {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // Sign out
          ListTile(
            tileColor: AppColors.surface,
            leading: const Icon(
              Icons.logout_rounded,
              color: AppColors.textSecondary,
            ),
            title: Text('Sign Out', style: AppTextStyles.body),
            trailing: const Icon(
              Icons.chevron_right,
              color: AppColors.textTertiary,
            ),
            onTap: _signingOut ? null : _signOut,
          ),
          _buildDivider(),

          // Delete account
          ListTile(
            tileColor: AppColors.surface,
            leading: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.negative,
            ),
            title: Text(
              'Delete Account',
              style: AppTextStyles.body.copyWith(color: AppColors.negative),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: AppColors.textTertiary,
            ),
            onTap: _deletingAccount ? null : _deleteAccount,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared inline feedback widgets
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
            style: AppTextStyles.caption.copyWith(color: AppColors.negative),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineSuccess(String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.check_circle_outline,
          color: AppColors.positive,
          size: AppSpacing.lg,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: AppTextStyles.caption.copyWith(color: AppColors.positive),
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      thickness: 1,
      color: AppColors.divider,
      indent: AppSpacing.lg,
    );
  }
}

// ---------------------------------------------------------------------------
// Private full-screen loading overlay
// ---------------------------------------------------------------------------

class _LoadingOverlay extends StatelessWidget {
  final String message;

  const _LoadingOverlay({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.loadingOverlay,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.positive),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(message, style: AppTextStyles.body),
          ],
        ),
      ),
    );
  }
}
