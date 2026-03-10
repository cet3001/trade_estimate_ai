import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

class NewEstimateScreen extends StatelessWidget {
  const NewEstimateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text('New Estimate Screen — Phase 5', style: AppTextStyles.heading1),
      ),
    );
  }
}
