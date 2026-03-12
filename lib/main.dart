import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/constants/env.dart';
import 'core/services/iap_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  ));

  // Read the env vars
  final supabaseUrl = Env.supabaseUrl;
  final supabaseAnonKey = Env.supabaseAnonKey;

  // Print resolved values so we can confirm dart-define is being picked up correctly.
  // The anon key is a public JWT — safe to log. Shows first 40 chars to verify identity.
  debugPrint('[Env] SUPABASE_URL="${supabaseUrl.isNotEmpty ? supabaseUrl : 'EMPTY – dart-define not set!'}"');
  debugPrint('[Env] SUPABASE_ANON_KEY="${supabaseAnonKey.isNotEmpty ? '${supabaseAnonKey.substring(0, supabaseAnonKey.length.clamp(0, 40))}...' : 'EMPTY – dart-define not set!'}"');

  // In debug, assert they're configured
  assert(supabaseUrl.isNotEmpty, 'SUPABASE_URL must be set via --dart-define=SUPABASE_URL=...');
  assert(supabaseAnonKey.isNotEmpty, 'SUPABASE_ANON_KEY must be set via --dart-define=SUPABASE_ANON_KEY=...');

  await Supabase.initialize(
    url: supabaseUrl.isNotEmpty ? supabaseUrl : 'https://placeholder.supabase.co',
    anonKey: supabaseAnonKey.isNotEmpty ? supabaseAnonKey : 'placeholder-anon-key',
  );

  await IapService().initialize();

  runApp(const TradeEstimateApp());
}
