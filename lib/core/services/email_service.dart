import 'package:supabase_flutter/supabase_flutter.dart';

class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  Future<void> sendEstimateToClient({
    required String estimateId,
    required String recipientEmail,
    required String recipientName,
  }) async {
    final response = await _client.functions.invoke(
      'send-estimate-email',
      body: {
        'estimate_id': estimateId,
        'recipient_email': recipientEmail,
        'recipient_name': recipientName,
      },
    );

    if (response.data == null) {
      throw Exception('Failed to send estimate email');
    }
  }
}
