import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_spacing.dart';
import '../core/constants/app_text_styles.dart';
import '../core/models/entitlements.dart';

class CreditBadge extends StatelessWidget {
  final Entitlements entitlements;
  final VoidCallback? onTap;

  const CreditBadge({
    super.key,
    required this.entitlements,
    this.onTap,
  });

  Color get _badgeColor {
    if (entitlements.isAdmin) return AppColors.positive;
    if (entitlements.hasActiveSubscription) return AppColors.positive;
    if (entitlements.creditsRemaining > 3) return AppColors.positive;
    if (entitlements.creditsRemaining > 0) return AppColors.warning;
    return AppColors.negative;
  }

  String get _badgeText {
    if (entitlements.isAdmin) return '\u221e Admin';
    if (entitlements.hasActiveSubscription) return 'Subscribed';
    if (entitlements.creditsRemaining == 0) return 'No credits';
    return '${entitlements.creditsRemaining} credits remaining';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.cardBorderRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: _badgeColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppSpacing.md),
            border: Border.all(color: _badgeColor.withValues(alpha: 0.40)),
          ),
          child: Row(
            children: [
              Container(
                width: AppSpacing.sm,
                height: AppSpacing.sm,
                decoration: BoxDecoration(
                  color: _badgeColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _badgeText,
                  style: AppTextStyles.body.copyWith(color: _badgeColor),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: AppSpacing.xl,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
