class UserProfile {
  // Sentinel used by copyWith to distinguish "not provided" from explicit null.
  static const _sentinel = Object();

  final String id;
  final String? fullName;
  final String? companyName;
  final String? contractorName;
  final String? email;
  final String? phone;
  final String? licenseNumber;
  final String? logoUrl;
  final String? emailSignature;
  final bool isAdmin;
  final String subscriptionStatus; // 'none' | 'active' | 'expired'
  final int creditsRemaining;
  final int totalEstimatesGenerated;
  final double? defaultLaborRate;
  final String? defaultTrade;
  final bool hasTeamAccess;
  final String? teamId;
  final String? teamRole;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    this.fullName,
    this.companyName,
    this.contractorName,
    this.email,
    this.phone,
    this.licenseNumber,
    this.logoUrl,
    this.emailSignature,
    this.isAdmin = false,
    this.subscriptionStatus = 'none',
    this.creditsRemaining = 0,
    this.totalEstimatesGenerated = 0,
    this.defaultLaborRate,
    this.defaultTrade,
    this.hasTeamAccess = false,
    this.teamId,
    this.teamRole,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      fullName: json['full_name'] as String?,
      companyName: json['company_name'] as String?,
      contractorName: json['contractor_name'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      licenseNumber: json['license_number'] as String?,
      logoUrl: json['logo_url'] as String?,
      emailSignature: json['email_signature'] as String?,
      isAdmin: (json['is_admin'] as bool?) ?? false,
      subscriptionStatus:
          (json['subscription_status'] as String?) ?? 'none',
      creditsRemaining: (json['credits_remaining'] as int?) ?? 0,
      totalEstimatesGenerated:
          (json['total_estimates_generated'] as int?) ?? 0,
      defaultLaborRate: (json['default_labor_rate'] as num?)?.toDouble(),
      defaultTrade: json['default_trade'] as String?,
      hasTeamAccess: (json['has_team_access'] as bool?) ?? false,
      teamId: json['team_id'] as String?,
      teamRole: json['team_role'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'company_name': companyName,
      'contractor_name': contractorName,
      'email': email,
      'phone': phone,
      'license_number': licenseNumber,
      'logo_url': logoUrl,
      'email_signature': emailSignature,
      'subscription_status': subscriptionStatus,
      'credits_remaining': creditsRemaining,
      'total_estimates_generated': totalEstimatesGenerated,
      'default_labor_rate': defaultLaborRate,
      'default_trade': defaultTrade,
      'team_id': teamId,
      'team_role': teamRole,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserProfile copyWith({
    Object? fullName = _sentinel,
    Object? companyName = _sentinel,
    Object? contractorName = _sentinel,
    Object? email = _sentinel,
    Object? phone = _sentinel,
    Object? licenseNumber = _sentinel,
    Object? logoUrl = _sentinel,
    Object? emailSignature = _sentinel,
    bool? isAdmin,
    String? subscriptionStatus,
    int? creditsRemaining,
    int? totalEstimatesGenerated,
    Object? defaultLaborRate = _sentinel,
    Object? defaultTrade = _sentinel,
    bool? hasTeamAccess,
    Object? teamId = _sentinel,
    Object? teamRole = _sentinel,
  }) {
    return UserProfile(
      id: id,
      fullName: fullName == _sentinel ? this.fullName : fullName as String?,
      companyName: companyName == _sentinel ? this.companyName : companyName as String?,
      contractorName: contractorName == _sentinel ? this.contractorName : contractorName as String?,
      email: email == _sentinel ? this.email : email as String?,
      phone: phone == _sentinel ? this.phone : phone as String?,
      licenseNumber: licenseNumber == _sentinel ? this.licenseNumber : licenseNumber as String?,
      logoUrl: logoUrl == _sentinel ? this.logoUrl : logoUrl as String?,
      emailSignature: emailSignature == _sentinel ? this.emailSignature : emailSignature as String?,
      isAdmin: isAdmin ?? this.isAdmin,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      creditsRemaining: creditsRemaining ?? this.creditsRemaining,
      totalEstimatesGenerated:
          totalEstimatesGenerated ?? this.totalEstimatesGenerated,
      defaultLaborRate: defaultLaborRate == _sentinel ? this.defaultLaborRate : defaultLaborRate as double?,
      defaultTrade: defaultTrade == _sentinel ? this.defaultTrade : defaultTrade as String?,
      hasTeamAccess: hasTeamAccess ?? this.hasTeamAccess,
      teamId: teamId == _sentinel ? this.teamId : teamId as String?,
      teamRole: teamRole == _sentinel ? this.teamRole : teamRole as String?,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
