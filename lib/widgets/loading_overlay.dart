import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_spacing.dart';
import '../core/constants/app_text_styles.dart';

/// Full-screen loading overlay that wraps a [child] widget.
///
/// When [isLoading] is true a dark overlay with a spinner and [message] is
/// rendered on top of [child] via a [Stack]. When false, only [child] is
/// shown with no overhead.
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final String message;
  final Widget child;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message = 'Loading...',
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: Container(
              color: AppColors.loadingOverlay,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.positive),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(message, style: AppTextStyles.body),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
