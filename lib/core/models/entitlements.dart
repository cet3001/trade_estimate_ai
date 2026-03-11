import 'user_profile.dart';

class Entitlements {
  final bool isAdmin;
  final bool hasActiveSubscription;
  final int creditsRemaining;

  bool get canGenerateEstimate =>
      isAdmin || hasActiveSubscription || creditsRemaining > 0;

  const Entitlements({
    this.isAdmin = false,
    required this.hasActiveSubscription,
    required this.creditsRemaining,
  });

  factory Entitlements.fromUserProfile(UserProfile profile) {
    return Entitlements(
      isAdmin: profile.isAdmin,
      hasActiveSubscription: profile.subscriptionStatus == 'active',
      creditsRemaining: profile.creditsRemaining,
    );
  }

  factory Entitlements.fromProfile(Map<String, dynamic> profile) {
    return Entitlements(
      isAdmin: profile['is_admin'] == true,
      hasActiveSubscription: profile['subscription_status'] == 'active',
      creditsRemaining: profile['credits_remaining'] ?? 0,
    );
  }

  static const Entitlements empty = Entitlements(
    isAdmin: false,
    hasActiveSubscription: false,
    creditsRemaining: 0,
  );
}
