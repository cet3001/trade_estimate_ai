import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Manages device session registration and validation for concurrent session
/// limiting. Only one device per account may hold an active session at a time.
///
/// - [registerDevice]: called after a successful sign-in to mark this device
///   as the active session.
/// - [isSessionValid]: called on app resume to check whether this device is
///   still the active session. Fails open on network errors.
class DeviceSessionService {
  static final DeviceSessionService _instance = DeviceSessionService._internal();
  factory DeviceSessionService() => _instance;
  DeviceSessionService._internal();

  String? _cachedDeviceId;

  Future<String> _getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final info = DeviceInfoPlugin();
    final ios = await info.iosInfo;
    _cachedDeviceId =
        ios.identifierForVendor ?? 'unknown-${DateTime.now().millisecondsSinceEpoch}';
    return _cachedDeviceId!;
  }

  /// Registers this device as the active session for the current user.
  /// Silently ignores all errors — never crashes the app.
  Future<void> registerDevice() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final deviceId = await _getDeviceId();
      await Supabase.instance.client.functions.invoke(
        'register-device',
        body: {
          'device_id': deviceId,
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[DeviceSession] registerDevice error: $e');
    }
  }

  /// Returns true if this device is still the active session.
  /// Returns true on any network error (fail-open).
  /// Uses a 3-second timeout to avoid blocking the UI.
  Future<bool> isSessionValid() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;

    try {
      final deviceId = await _getDeviceId();
      final response = await Supabase.instance.client.functions
          .invoke('check-device-session', body: {'device_id': deviceId})
          .timeout(const Duration(seconds: 3));

      if (response.status != 200) return true; // fail-open
      final data = response.data as Map<String, dynamic>?;
      return (data?['valid'] as bool?) ?? true;
    } catch (e) {
      // Network error, timeout, or any other failure → fail-open
      if (kDebugMode) debugPrint('[DeviceSession] isSessionValid error: $e');
      return true;
    }
  }
}
