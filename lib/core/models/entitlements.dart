import 'user_profile.dart';

class Entitlements {
  final bool isAdmin;
  final bool hasActiveSubscription;
  final int creditsRemaining;
  final bool hasTeamAccess;

  bool get canGenerateEstimate =>
      isAdmin || hasActiveSubscription || creditsRemaining > 0 || hasTeamAccess;

  const Entitlements({
    this.isAdmin = false,
    required this.hasActiveSubscription,
    required this.creditsRemaining,
    this.hasTeamAccess = false,
  });

  factory Entitlements.fromUserProfile(UserProfile profile) {
    return Entitlements(
      isAdmin: profile.isAdmin,
      hasActiveSubscription: profile.subscriptionStatus == 'active',
      creditsRemaining: profile.creditsRemaining,
      hasTeamAccess: profile.hasTeamAccess,
    );
  }

  factory Entitlements.fromProfile(Map<String, dynamic> profile) {
    return Entitlements(
      isAdmin: profile['is_admin'] == true,
      hasActiveSubscription: profile['subscription_status'] == 'active',
      creditsRemaining: profile['credits_remaining'] ?? 0,
      hasTeamAccess: profile['has_team_access'] == true,
    );
  }

  static const Entitlements empty = Entitlements(
    isAdmin: false,
    hasActiveSubscription: false,
    creditsRemaining: 0,
  );
}
