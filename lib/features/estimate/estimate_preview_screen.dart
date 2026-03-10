import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

class EstimatePreviewScreen extends StatelessWidget {
  final String estimateId;
  const EstimatePreviewScreen({super.key, required this.estimateId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text('Estimate Preview Screen — Phase 5', style: AppTextStyles.heading1),
      ),
    );
  }
}
