class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  // Anthropic API key is NEVER stored client-side.
  // It lives in Supabase Edge Functions only.
}
