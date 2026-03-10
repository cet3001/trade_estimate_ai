// Anthropic calls are routed entirely through Supabase Edge Functions.
// This service is a thin wrapper around the edge function invocation.

import 'package:supabase_flutter/supabase_flutter.dart';

class AnthropicService {
  static final AnthropicService _instance = AnthropicService._internal();
  factory AnthropicService() => _instance;
  AnthropicService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  Future<Map<String, dynamic>> generateEstimate({
    required String trade,
    required String jobTitle,
    required String jobDescription,
    required Map<String, dynamic> scopeDetails,
    required double laborHours,
    required double laborRate,
    required double materialsCost,
    double? additionalFees,
    required String clientName,
    required String clientEmail,
    String? jobLocation,
    String? notes,
    required String businessName,
    String? licenseNumber,
  }) async {
    final response = await _client.functions.invoke(
      'generate-estimate',
      body: {
        'trade': trade,
        'jobTitle': jobTitle,
        'jobDescription': jobDescription,
        'scopeDetails': scopeDetails,
        'laborHours': laborHours,
        'laborRate': laborRate,
        'materialsCost': materialsCost,
        'additionalFees': additionalFees ?? 0,
        'clientName': clientName,
        'clientEmail': clientEmail,
        'jobLocation': jobLocation,
        'notes': notes,
        'businessName': businessName,
        'licenseNumber': licenseNumber,
      },
    );

    if (response.data == null) {
      throw Exception('Failed to generate estimate: no data returned');
    }

    return response.data as Map<String, dynamic>;
  }
}
