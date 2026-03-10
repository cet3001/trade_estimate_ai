import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../core/constants/app_spacing.dart';
import '../core/constants/trade_templates.dart';

class TradeSelectorTile extends StatelessWidget {
  final TradeType trade;
  final bool isSelected;
  final VoidCallback onTap;

  const TradeSelectorTile({
    super.key,
    required this.trade,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.positive.withValues(alpha: 0.1)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.borderActive : AppColors.borderDefault,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    trade.emoji,
                    style: const TextStyle(fontSize: AppSpacing.tradeTileEmojiSize),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    trade.displayName,
                    style: AppTextStyles.heading2.copyWith(
                      color: isSelected ? AppColors.positive : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: AppColors.positive,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: AppColors.textPrimary,
                    size: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
