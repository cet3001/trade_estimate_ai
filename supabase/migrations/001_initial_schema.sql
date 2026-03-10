-- Users/profiles
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  company_name TEXT,
  email TEXT,
  phone TEXT,
  license_number TEXT,
  logo_url TEXT,
  subscription_status TEXT DEFAULT 'none',
  credits_remaining INTEGER DEFAULT 0,
  default_labor_rate NUMERIC,
  total_estimates_generated INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Estimates
CREATE TABLE estimates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  trade TEXT NOT NULL,
  client_name TEXT,
  client_email TEXT,
  job_title TEXT,
  job_description TEXT,
  scope_of_work TEXT,
  materials TEXT,
  job_location TEXT,
  scope_details JSONB,
  notes TEXT,
  labor_hours NUMERIC,
  labor_rate NUMERIC,
  materials_cost NUMERIC,
  additional_fees NUMERIC DEFAULT 0,
  total_estimate NUMERIC,
  ai_generated_body TEXT,
  pdf_url TEXT,
  status TEXT DEFAULT 'draft',
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- IAP receipts
CREATE TABLE iap_receipts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES profiles(id),
  product_id TEXT,
  transaction_id TEXT UNIQUE,
  purchase_date TIMESTAMPTZ,
  expires_date TIMESTAMPTZ,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE estimates ENABLE ROW LEVEL SECURITY;
ALTER TABLE iap_receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own profile" ON profiles
  FOR ALL USING (auth.uid() = id);
CREATE POLICY "Users manage own estimates" ON estimates
  FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users manage own receipts" ON iap_receipts
  FOR ALL USING (auth.uid() = user_id);

-- Indexes for common query patterns
CREATE INDEX idx_estimates_user_created ON estimates(user_id, created_at DESC);
CREATE INDEX idx_iap_receipts_user ON iap_receipts(user_id);

-- Atomic credit increment RPC
CREATE OR REPLACE FUNCTION add_credits(p_user_id UUID, amount INTEGER)
RETURNS VOID AS $$
BEGIN
  UPDATE profiles
  SET credits_remaining = credits_remaining + amount,
      updated_at = NOW()
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- MANUAL STEP REQUIRED: Supabase Storage Bucket
-- ============================================================
-- Create a private storage bucket named 'estimate-pdfs' via:
--   1. Supabase Dashboard > Storage > New Bucket
--   2. Name: estimate-pdfs
--   3. Public: NO (private/authenticated access only)
-- Or via Supabase Management API:
--   POST /v1/projects/{ref}/storage/buckets
--   { "id": "estimate-pdfs", "name": "estimate-pdfs", "public": false }
-- ============================================================
