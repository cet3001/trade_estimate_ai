import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/models/entitlements.dart';
import '../../core/models/estimate.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/supabase_service.dart';
import '../../widgets/credit_badge.dart';
import '../../widgets/estimate_card.dart';
import '../paywall/paywall_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Singleton — factory always returns the same instance
  final _service = SupabaseService();

  bool _loading = true;
  String? _error;

  UserProfile? _profile;
  List<Estimate> _estimates = [];
  List<Estimate> _recentEstimates = [];

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _service.getProfile(),
        _service.getEstimates(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as UserProfile?;
        _estimates = results[1] as List<Estimate>;
        _recentEstimates = _estimates.take(5).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('HomeScreen._loadData error: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Please check your connection and try again.';
        _loading = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Derived data
  // ---------------------------------------------------------------------------

  Entitlements get _entitlements {
    if (_profile == null) return Entitlements.empty;
    return Entitlements.fromUserProfile(_profile!);
  }

  // ---------------------------------------------------------------------------
  // Navigation helpers
  // ---------------------------------------------------------------------------

  void _openPaywall() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaywallScreen(onSuccess: _loadData),
      ),
    );
  }

  void _openSettings() => Navigator.of(context).pushNamed('/settings');

  void _onNewEstimate() {
    if (_entitlements.canGenerateEstimate) {
      Navigator.of(context).pushNamed('/estimate/new');
    } else {
      _openPaywall();
    }
  }

  void _openEstimate(Estimate estimate) {
    Navigator.of(context).pushNamed(
      '/estimate/preview',
      arguments: estimate,
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  AppBar _buildAppBar() {
    final initials = _profileInitials();
    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      title: Text('Trade Estimate AI', style: AppTextStyles.heading2),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.lg),
          child: Material(
            color: AppColors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _openSettings,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: CircleAvatar(
                  radius: AppSpacing.xl,
                  backgroundColor: AppColors.surfaceElevated,
                  child: Text(
                    initials,
                    style: AppTextStyles.label.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _profileInitials() {
    final name = _profile?.fullName;
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0][0].toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError();
    return _buildContent();
  }

  // ---------------------------------------------------------------------------
  // States
  // ---------------------------------------------------------------------------

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.positive),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.negative,
              size: AppSpacing.huge,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Failed to load data',
              style: AppTextStyles.heading2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error ?? '',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              height: AppSpacing.buttonHeight,
              child: ElevatedButton(
                onPressed: _loadData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.md),
                  ),
                ),
                child: Text('Retry', style: AppTextStyles.body),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Main content
  // ---------------------------------------------------------------------------

  Widget _buildContent() {
    return RefreshIndicator(
      color: AppColors.positive,
      backgroundColor: AppColors.surface,
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        children: [
          // Credit badge
          CreditBadge(
            entitlements: _entitlements,
            onTap: _openPaywall,
          ),
          const SizedBox(height: AppSpacing.lg),

          // New Estimate CTA
          _buildNewEstimateButton(),
          const SizedBox(height: AppSpacing.xxl),

          // Recent Estimates section
          _buildSectionHeader('Recent Estimates'),
          const SizedBox(height: AppSpacing.md),
          _buildRecentEstimates(),
          const SizedBox(height: AppSpacing.xxl),

          // All Estimates section
          _buildSectionHeader('All Estimates'),
          const SizedBox(height: AppSpacing.md),
          _buildAllEstimates(),

          // Bottom padding for safe area
          const SizedBox(height: AppSpacing.huge),
        ],
      ),
    );
  }

  Widget _buildNewEstimateButton() {
    return SizedBox(
      width: double.infinity,
      height: AppSpacing.buttonHeight,
      child: ElevatedButton(
        onPressed: _onNewEstimate,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.positive,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.md),
          ),
        ),
        child: Text(
          '+ New Estimate',
          style: AppTextStyles.heading2.copyWith(color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: AppTextStyles.heading2);
  }

  // ---------------------------------------------------------------------------
  // Recent Estimates — horizontal scroll
  // ---------------------------------------------------------------------------

  Widget _buildRecentEstimates() {
    if (_recentEstimates.isEmpty) {
      return _buildEmptyInline('No estimates yet');
    }
    return SizedBox(
      height: AppSpacing.recentEstimatesListHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _recentEstimates.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, index) {
          final estimate = _recentEstimates[index];
          return EstimateCard(
            estimate: estimate,
            compact: true,
            onTap: () => _openEstimate(estimate),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // All Estimates — vertical list
  // ---------------------------------------------------------------------------

  Widget _buildAllEstimates() {
    if (_estimates.isEmpty) {
      return _buildAllEstimatesEmptyState();
    }
    return ListView.separated(
      // Nested inside the outer ListView — disable scrolling so it renders
      // as a static list inside the scroll view.
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true, // TODO: add server-side pagination when estimate counts grow
      itemCount: _estimates.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final estimate = _estimates[index];
        return EstimateCard(
          estimate: estimate,
          compact: false,
          onTap: () => _openEstimate(estimate),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Empty states
  // ---------------------------------------------------------------------------

  Widget _buildEmptyInline(String message) {
    return SizedBox(
      height: AppSpacing.emptyStateInlineHeight,
      child: Center(
        child: Text(message, style: AppTextStyles.caption),
      ),
    );
  }

  Widget _buildAllEstimatesEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.description_outlined,
            color: AppColors.textTertiary,
            size: AppSpacing.huge,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No estimates yet',
            style: AppTextStyles.heading2.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tap \u201C+ New Estimate\u201D to create your first one.',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
