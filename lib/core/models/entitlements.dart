import 'user_profile.dart';

class Entitlements {
  final bool hasActiveSubscription;
  final int creditsRemaining;

  bool get canGenerateEstimate =>
      hasActiveSubscription || creditsRemaining > 0;

  const Entitlements({
    required this.hasActiveSubscription,
    required this.creditsRemaining,
  });

  factory Entitlements.fromProfile(Map<String, dynamic> profile) {
    return Entitlements(
      hasActiveSubscription:
          profile['subscription_status'] == 'active',
      creditsRemaining: (profile['credits_remaining'] as int?) ?? 0,
    );
  }

  factory Entitlements.fromUserProfile(UserProfile profile) {
    return Entitlements(
      hasActiveSubscription: profile.subscriptionStatus == 'active',
      creditsRemaining: profile.creditsRemaining,
    );
  }

  static const Entitlements empty = Entitlements(
    hasActiveSubscription: false,
    creditsRemaining: 0,
  );
}
