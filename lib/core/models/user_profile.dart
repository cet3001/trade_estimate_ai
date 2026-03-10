class UserProfile {
  final String id;
  final String? fullName;
  final String? companyName;
  final String? email;
  final String? phone;
  final String? licenseNumber;
  final String? logoUrl;
  final String subscriptionStatus; // 'none' | 'active' | 'expired'
  final int creditsRemaining;
  final int totalEstimatesGenerated;
  final double? defaultLaborRate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    this.fullName,
    this.companyName,
    this.email,
    this.phone,
    this.licenseNumber,
    this.logoUrl,
    this.subscriptionStatus = 'none',
    this.creditsRemaining = 0,
    this.totalEstimatesGenerated = 0,
    this.defaultLaborRate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      fullName: json['full_name'] as String?,
      companyName: json['company_name'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      licenseNumber: json['license_number'] as String?,
      logoUrl: json['logo_url'] as String?,
      subscriptionStatus:
          (json['subscription_status'] as String?) ?? 'none',
      creditsRemaining: (json['credits_remaining'] as int?) ?? 0,
      totalEstimatesGenerated:
          (json['total_estimates_generated'] as int?) ?? 0,
      defaultLaborRate: (json['default_labor_rate'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'company_name': companyName,
      'email': email,
      'phone': phone,
      'license_number': licenseNumber,
      'logo_url': logoUrl,
      'subscription_status': subscriptionStatus,
      'credits_remaining': creditsRemaining,
      'total_estimates_generated': totalEstimatesGenerated,
      'default_labor_rate': defaultLaborRate,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? fullName,
    String? companyName,
    String? email,
    String? phone,
    String? licenseNumber,
    String? logoUrl,
    String? subscriptionStatus,
    int? creditsRemaining,
    int? totalEstimatesGenerated,
    double? defaultLaborRate,
  }) {
    return UserProfile(
      id: id,
      fullName: fullName ?? this.fullName,
      companyName: companyName ?? this.companyName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      logoUrl: logoUrl ?? this.logoUrl,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      creditsRemaining: creditsRemaining ?? this.creditsRemaining,
      totalEstimatesGenerated:
          totalEstimatesGenerated ?? this.totalEstimatesGenerated,
      defaultLaborRate: defaultLaborRate ?? this.defaultLaborRate,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
