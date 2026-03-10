import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

class EstimateHistoryScreen extends StatelessWidget {
  const EstimateHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text('Estimate History Screen — Phase 4', style: AppTextStyles.heading1),
      ),
    );
  }
}
