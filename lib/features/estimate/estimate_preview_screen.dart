import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/models/estimate.dart';

class EstimatePreviewScreen extends StatelessWidget {
  /// Full [Estimate] object passed directly (preferred — avoids a round-trip).
  final Estimate? estimate;

  /// Fallback: fetch the estimate by ID when [estimate] is not provided.
  final String estimateId;

  const EstimatePreviewScreen({
    super.key,
    this.estimate,
    this.estimateId = '',
  });

  @override
  Widget build(BuildContext context) {
    // Phase 5 will use [estimate] directly when available, or fetch by
    // [estimateId] when only the ID is provided.
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text('Estimate Preview Screen — Phase 5', style: AppTextStyles.heading1),
      ),
    );
  }
}
