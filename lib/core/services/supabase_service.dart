import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/trade_templates.dart';
import '../models/user_profile.dart';
import '../models/estimate.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final _secureStorage = const FlutterSecureStorage();
  static const _onboardingKey = 'has_completed_onboarding';

  SupabaseClient get client => Supabase.instance.client;
  User? get currentUser => client.auth.currentUser;
  Session? get currentSession => client.auth.currentSession;

  // Auth
  Future<void> signInWithApple() async {
    await client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: 'tradeestimateai://auth/callback',
    );
  }

  Future<void> signOut() async {
    await client.auth.signOut();
    await _secureStorage.delete(key: _onboardingKey);
  }

  Future<bool> hasCompletedOnboarding() async {
    final value = await _secureStorage.read(key: _onboardingKey);
    return value == 'true';
  }

  Future<void> setOnboardingComplete() async {
    await _secureStorage.write(key: _onboardingKey, value: 'true');
  }

  // Profile
  Future<UserProfile?> getProfile() async {
    final userId = currentUser?.id;
    if (userId == null) return null;

    final response = await client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (response == null) return null;
    return UserProfile.fromJson(response);
  }

  Future<UserProfile?> createProfile({
    required String fullName,
    required String companyName,
    required String email,
    String? phone,
    String? licenseNumber,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    final now = DateTime.now().toIso8601String();

    final data = {
      'id': userId,
      'full_name': fullName,
      'company_name': companyName,
      'email': email,
      'phone': phone,
      'license_number': licenseNumber,
      'subscription_status': 'none',
      'credits_remaining': 0,
      'total_estimates_generated': 0,
      'created_at': now,
      'updated_at': now,
    };

    final response = await client
        .from('profiles')
        .upsert(data)
        .select()
        .single();

    return UserProfile.fromJson(response);
  }

  Future<UserProfile?> updateProfile(Map<String, dynamic> updates) async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    updates['updated_at'] = DateTime.now().toIso8601String();

    final response = await client
        .from('profiles')
        .update(updates)
        .eq('id', userId)
        .select()
        .single();

    return UserProfile.fromJson(response);
  }

  // Estimates
  Future<List<Estimate>> getEstimates() async {
    final userId = currentUser?.id;
    if (userId == null) return [];

    final response = await client
        .from('estimates')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((e) => Estimate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Estimate?> getEstimate(String id) async {
    final response = await client
        .from('estimates')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return Estimate.fromJson(response);
  }

  Future<Estimate?> duplicateEstimate(Estimate original) async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    final now = DateTime.now().toIso8601String();

    final data = {
      'user_id': userId,
      'trade': original.trade.value,
      'client_name': original.clientName,
      'client_email': original.clientEmail,
      'job_title': original.jobTitle,
      'job_description': original.jobDescription,
      'job_location': original.jobLocation,
      'scope_details': original.scopeDetails,
      'notes': original.notes,
      'labor_hours': original.laborHours,
      'labor_rate': original.laborRate,
      'materials_cost': original.materialsCost,
      'additional_fees': original.additionalFees,
      'total_estimate': original.totalEstimate,
      'ai_generated_body': original.aiGeneratedBody,
      'status': 'draft',
      'sent_at': null,
      'created_at': now,
    };

    final response = await client
        .from('estimates')
        .insert(data)
        .select()
        .single();

    return Estimate.fromJson(response);
  }

  Future<void> deleteEstimate(String id) async {
    await client.from('estimates').delete().eq('id', id);
  }

  Future<void> updateEstimateStatus(String id, String status) async {
    final updates = <String, dynamic>{'status': status};
    if (status == 'sent') {
      updates['sent_at'] = DateTime.now().toIso8601String();
    }
    await client.from('estimates').update(updates).eq('id', id);
  }

  Future<void> updateEstimateBody(String id, String body) async {
    await client
        .from('estimates')
        .update({'ai_generated_body': body})
        .eq('id', id);
  }

  Future<void> updateEstimatePdfUrl(String id, String url) async {
    await client
        .from('estimates')
        .update({'pdf_url': url})
        .eq('id', id);
  }

  /// Upload [bytes] as a PDF to Supabase Storage and return the public URL.
  /// Bucket: 'estimates', path: estimate-pdfs/{userId}/{estimateId}.pdf
  Future<String> uploadEstimatePdf({
    required String estimateId,
    required Uint8List bytes,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) throw Exception('No authenticated user');

    final storagePath = 'estimate-pdfs/$userId/$estimateId.pdf';

    await client.storage.from('estimates').uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: true,
          ),
        );

    return client.storage.from('estimates').getPublicUrl(storagePath);
  }

  // Edge Functions
  Future<Estimate> generateEstimate(Map<String, dynamic> body) async {
    final response = await client.functions
        .invoke('generate-estimate', body: body);
    final data = response.data as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Empty response from generate-estimate');
    }
    final estimateJson = data['estimate'] as Map<String, dynamic>? ?? data;
    return Estimate.fromJson(estimateJson);
  }

  // Delete account
  Future<void> deleteAccount() async {
    final userId = currentUser?.id;
    if (userId == null) return;
    // Deletes cascade via FK constraints
    await client.from('profiles').delete().eq('id', userId);
    await client.auth.signOut();
  }
}
