-- Add environment and verified_at columns to iap_receipts
-- Add unique constraint on transaction_id for idempotency / TOCTOU protection

ALTER TABLE iap_receipts
  ADD COLUMN IF NOT EXISTS environment TEXT NOT NULL DEFAULT 'Production',
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;

ALTER TABLE iap_receipts
  DROP CONSTRAINT IF EXISTS iap_receipts_transaction_id_key;

ALTER TABLE iap_receipts
  ADD CONSTRAINT iap_receipts_transaction_id_key UNIQUE (transaction_id);

-- Add subscription_expires_at to profiles so the edge function can record
-- when a monthly subscription expires (sourced from Apple's expiresDate field).
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS subscription_expires_at TIMESTAMPTZ;

-- increment_credits RPC: alias called by the new verify-iap-receipt implementation.
-- The older add_credits(p_user_id, p_amount) function remains untouched.
CREATE OR REPLACE FUNCTION increment_credits(user_id UUID, amount INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE profiles
  SET credits_remaining = credits_remaining + amount,
      updated_at = NOW()
  WHERE id = user_id;
END;
$$;
