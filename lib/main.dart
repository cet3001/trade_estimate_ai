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
