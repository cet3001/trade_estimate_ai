import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/app_colors.dart';
import 'core/constants/app_spacing.dart';
import 'core/models/estimate.dart';
import 'core/services/supabase_service.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/estimate/new_estimate_screen.dart';
import 'features/estimate/estimate_preview_screen.dart';
import 'features/estimate/estimate_history_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/paywall/paywall_screen.dart';

class TradeEstimateApp extends StatelessWidget {
  const TradeEstimateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trade Estimate AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.positive,
          secondary: AppColors.accent,
          surface: AppColors.surface,
          error: AppColors.negative,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          iconTheme: IconThemeData(color: AppColors.textPrimary),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.md),
            borderSide: const BorderSide(color: AppColors.borderDefault),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.md),
            borderSide: const BorderSide(color: AppColors.borderDefault),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.md),
            borderSide: const BorderSide(color: AppColors.borderActive, width: 2),
          ),
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          hintStyle: const TextStyle(color: AppColors.textTertiary),
        ),
        dividerColor: AppColors.divider,
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const _AppRouter(),
        '/auth': (context) => const AuthScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/home': (context) => const HomeScreen(),
        '/new-estimate': (context) => const NewEstimateScreen(),
        '/history': (context) => const EstimateHistoryScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/paywall': (context) => const PaywallScreen(),
      },
      onGenerateRoute: (settings) {
        // Legacy route used internally
        if (settings.name == '/estimate-preview') {
          final estimateId = settings.arguments as String?;
          return MaterialPageRoute(
            builder: (context) => EstimatePreviewScreen(
              estimateId: estimateId ?? '',
            ),
          );
        }
        // Phase 4+ spec routes
        if (settings.name == '/estimate/new') {
          final prefill = settings.arguments is Estimate
              ? settings.arguments as Estimate
              : null;
          return MaterialPageRoute(
            builder: (context) => NewEstimateScreen(prefillEstimate: prefill),
          );
        }
        if (settings.name == '/estimate/preview') {
          final arg = settings.arguments;
          if (arg is Estimate) {
            return MaterialPageRoute(
              builder: (context) => EstimatePreviewScreen(estimate: arg),
            );
          }
          final estimateId = arg is String ? arg : '';
          return MaterialPageRoute(
            builder: (context) => EstimatePreviewScreen(estimateId: estimateId),
          );
        }
        return null;
      },
    );
  }
}

// Router that checks auth state at cold launch and redirects appropriately.
// The route determination is done before the first meaningful frame so the
// user never sees the auth screen flash before being sent to /home.
class _AppRouter extends StatefulWidget {
  const _AppRouter();

  @override
  State<_AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<_AppRouter> {
  @override
  void initState() {
    super.initState();
    // Schedule the route check after the first frame so that Navigator is ready,
    // but we already computed the route synchronously where possible.
    WidgetsBinding.instance.addPostFrameCallback((_) => _determineInitialRoute());
  }

  Future<void> _determineInitialRoute() async {
    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      // Check if session is expired.
      // isExpired has a 30-second lookahead window, so a live auto-refreshable
      // session may appear expired. Attempt a silent refresh first.
      if (session.isExpired) {
        try {
          await Supabase.instance.client.auth.refreshSession();
          // Refresh succeeded — session is now valid; fall through to
          // home/onboarding routing below.
        } catch (_) {
          // Refresh failed — session is truly expired.
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed(
            '/auth',
            arguments: <String, dynamic>{'welcomeBack': true},
          );
          return;
        }
      }

      // Valid session — check onboarding flag
      final onboardingDone = await SupabaseService().hasCompletedOnboarding();
      if (!mounted) return;
      if (onboardingDone) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
    } else {
      // No session — show auth
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show a branded splash while the route is being determined.
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.positive),
        ),
      ),
    );
  }
}
