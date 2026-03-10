import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_spacing.dart';
import '../core/constants/app_text_styles.dart';
import '../core/constants/trade_templates.dart';
import '../core/models/estimate.dart';
import '../core/utils/formatters.dart';

class EstimateCard extends StatelessWidget {
  final Estimate estimate;
  final VoidCallback? onTap;

  /// When [compact] is true, renders a fixed-width card for the horizontal
  /// recent-estimates list (~160 px wide).
  /// When false (default), renders a full-width row for the vertical list.
  final bool compact;

  const EstimateCard({
    super.key,
    required this.estimate,
    this.onTap,
    this.compact = false,
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Color get _tradeColor {
    switch (estimate.trade) {
      case TradeType.plumbing:
        return AppColors.plumbing;
      case TradeType.electrical:
        return AppColors.electrical;
      case TradeType.roofing:
        return AppColors.roofing;
      case TradeType.construction:
        return AppColors.construction;
    }
  }

  IconData get _tradeIcon {
    switch (estimate.trade) {
      case TradeType.plumbing:
        return Icons.plumbing;
      case TradeType.electrical:
        return Icons.electrical_services;
      case TradeType.roofing:
        return Icons.roofing;
      case TradeType.construction:
        return Icons.construction;
    }
  }

  Color get _statusColor {
    switch (estimate.status) {
      case 'sent':
        return AppColors.accent;
      case 'accepted':
        return AppColors.positive;
      case 'declined':
        return AppColors.negative;
      default: // 'draft'
        return AppColors.textTertiary;
    }
  }

  String get _statusLabel {
    switch (estimate.status) {
      case 'sent':
        return 'Sent';
      case 'accepted':
        return 'Accepted';
      case 'declined':
        return 'Declined';
      default:
        return 'Draft';
    }
  }

  String get _cardDate {
    return DateFormat('MMM d').format(estimate.createdAt);
  }

  Widget _statusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.cardBorderRadius),
      ),
      child: Text(
        _statusLabel,
        style: AppTextStyles.caption.copyWith(
          color: _statusColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Compact card (horizontal recent list)
  // ---------------------------------------------------------------------------

  Widget _buildCompact() {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: AppSpacing.estimateCardCompactWidth,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.md),
          border: Border(
            left: BorderSide(color: _tradeColor, width: AppSpacing.cardAccentBorderWidth),
            top: const BorderSide(color: AppColors.divider),
            right: const BorderSide(color: AppColors.divider),
            bottom: const BorderSide(color: AppColors.divider),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_tradeIcon, color: _tradeColor, size: AppSpacing.xl),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      estimate.trade.displayName,
                      style: AppTextStyles.label.copyWith(color: _tradeColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                estimate.clientName ?? 'Unknown',
                style: AppTextStyles.heading2,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                Formatters.currency(estimate.totalEstimate),
                style: AppTextStyles.totalAmount,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.sm),
              _statusBadge(),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _cardDate,
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Full-width row (vertical all-estimates list)
  // ---------------------------------------------------------------------------

  Widget _buildFullWidth() {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.md),
          border: Border(
            left: BorderSide(color: _tradeColor, width: AppSpacing.cardAccentBorderWidth),
            top: const BorderSide(color: AppColors.divider),
            right: const BorderSide(color: AppColors.divider),
            bottom: const BorderSide(color: AppColors.divider),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              // Trade icon
              Container(
                width: AppSpacing.xxxl + AppSpacing.sm,
                height: AppSpacing.xxxl + AppSpacing.sm,
                decoration: BoxDecoration(
                  color: _tradeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.sm),
                ),
                child: Icon(_tradeIcon, color: _tradeColor, size: AppSpacing.xl),
              ),
              const SizedBox(width: AppSpacing.md),
              // Client + job title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      estimate.clientName ?? 'Unknown',
                      style: AppTextStyles.heading2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (estimate.jobTitle != null &&
                        estimate.jobTitle!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        estimate.jobTitle!,
                        style: AppTextStyles.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Total + status + date stacked
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.currency(estimate.totalEstimate),
                    style: AppTextStyles.totalAmount,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _statusBadge(),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _cardDate,
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return compact ? _buildCompact() : _buildFullWidth();
  }
}
