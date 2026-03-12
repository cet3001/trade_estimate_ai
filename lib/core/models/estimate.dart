import '../constants/trade_templates.dart';

class Estimate {
  // Sentinel used by copyWith to distinguish "omitted" from explicit null.
  static const Object _sentinel = Object();

  final String id;
  final String userId;
  final TradeType trade;
  final String? clientName;
  final String? clientEmail;
  final String? jobTitle;
  final String? jobDescription;
  final String? scopeOfWork;
  final String? materials;
  final String? jobLocation;
  final Map<String, dynamic>? scopeDetails;
  final String? notes;
  final double? laborHours;
  final double? laborRate;
  final double? materialsCost;
  final double? additionalFees;
  final double? totalEstimate;
  final String? aiGeneratedBody;
  final String? pdfUrl;
  final String status; // 'draft' | 'sent' | 'accepted' | 'declined'
  final DateTime? sentAt;
  final DateTime createdAt;

  const Estimate({
    required this.id,
    required this.userId,
    required this.trade,
    this.clientName,
    this.clientEmail,
    this.jobTitle,
    this.jobDescription,
    this.scopeOfWork,
    this.materials,
    this.jobLocation,
    this.scopeDetails,
    this.notes,
    this.laborHours,
    this.laborRate,
    this.materialsCost,
    this.additionalFees,
    this.totalEstimate,
    this.aiGeneratedBody,
    this.pdfUrl,
    this.status = 'draft',
    this.sentAt,
    required this.createdAt,
  });

  factory Estimate.fromJson(Map<String, dynamic> json) {
    return Estimate(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      trade: TradeTypeExtension.fromString(json['trade'] as String),
      clientName: json['client_name'] as String?,
      clientEmail: json['client_email'] as String?,
      jobTitle: json['job_title'] as String?,
      jobDescription: json['job_description'] as String?,
      scopeOfWork: json['scope_of_work'] as String?,
      materials: json['materials'] as String?,
      jobLocation: json['job_location'] as String?,
      scopeDetails: json['scope_details'] as Map<String, dynamic>?,
      notes: json['notes'] as String?,
      laborHours: (json['labor_hours'] as num?)?.toDouble(),
      laborRate: (json['labor_rate'] as num?)?.toDouble(),
      materialsCost: (json['materials_cost'] as num?)?.toDouble(),
      additionalFees: (json['additional_fees'] as num?)?.toDouble(),
      totalEstimate: (json['total_estimate'] as num?)?.toDouble(),
      aiGeneratedBody: json['ai_generated_body'] as String?,
      pdfUrl: json['pdf_url'] as String?,
      status: (json['status'] as String?) ?? 'draft',
      sentAt: json['sent_at'] != null
          ? DateTime.parse(json['sent_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'trade': trade.value,
      'client_name': clientName,
      'client_email': clientEmail,
      'job_title': jobTitle,
      'job_description': jobDescription,
      'scope_of_work': scopeOfWork,
      'materials': materials,
      'job_location': jobLocation,
      'scope_details': scopeDetails,
      'notes': notes,
      'labor_hours': laborHours,
      'labor_rate': laborRate,
      'materials_cost': materialsCost,
      'additional_fees': additionalFees,
      'total_estimate': totalEstimate,
      'ai_generated_body': aiGeneratedBody,
      'pdf_url': pdfUrl,
      'status': status,
      'sent_at': sentAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  Estimate copyWith({
    String? id,
    String? userId,
    TradeType? trade,
    String? clientName,
    String? clientEmail,
    String? jobTitle,
    String? jobDescription,
    String? scopeOfWork,
    String? materials,
    String? jobLocation,
    Map<String, dynamic>? scopeDetails,
    String? notes,
    double? laborHours,
    double? laborRate,
    double? materialsCost,
    double? additionalFees,
    double? totalEstimate,
    Object? aiGeneratedBody = _sentinel,
    Object? pdfUrl = _sentinel,
    String? status,
    Object? sentAt = _sentinel,
    DateTime? createdAt,
  }) {
    return Estimate(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      trade: trade ?? this.trade,
      clientName: clientName ?? this.clientName,
      clientEmail: clientEmail ?? this.clientEmail,
      jobTitle: jobTitle ?? this.jobTitle,
      jobDescription: jobDescription ?? this.jobDescription,
      scopeOfWork: scopeOfWork ?? this.scopeOfWork,
      materials: materials ?? this.materials,
      jobLocation: jobLocation ?? this.jobLocation,
      scopeDetails: scopeDetails ?? this.scopeDetails,
      notes: notes ?? this.notes,
      laborHours: laborHours ?? this.laborHours,
      laborRate: laborRate ?? this.laborRate,
      materialsCost: materialsCost ?? this.materialsCost,
      additionalFees: additionalFees ?? this.additionalFees,
      totalEstimate: totalEstimate ?? this.totalEstimate,
      aiGeneratedBody: identical(aiGeneratedBody, _sentinel)
          ? this.aiGeneratedBody
          : aiGeneratedBody as String?,
      pdfUrl: identical(pdfUrl, _sentinel) ? this.pdfUrl : pdfUrl as String?,
      status: status ?? this.status,
      sentAt:
          identical(sentAt, _sentinel) ? this.sentAt : sentAt as DateTime?,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  double get computedTotal {
    final labor = (laborHours ?? 0) * (laborRate ?? 0);
    final materials = materialsCost ?? 0;
    final additional = additionalFees ?? 0;
    return labor + materials + additional;
  }
}
