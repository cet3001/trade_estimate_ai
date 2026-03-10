-- Migration: 20240002_add_credits_rpc
--
-- Fixes the add_credits function signature: renames the second parameter from
-- `amount` to `p_amount` to match the named-argument calls in the edge functions
-- (verify-iap-receipt calls add_credits(p_user_id, p_amount)).
--
-- Also creates increment_estimates_generated, which generate-estimate calls via
-- supabaseAdmin.rpc('increment_estimates_generated', { p_user_id }).

-- Re-create add_credits with the p_amount parameter name expected by edge functions.
-- Also stamps updated_at so the profile row reflects the change time.
CREATE OR REPLACE FUNCTION add_credits(p_user_id UUID, p_amount INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE profiles
  SET credits_remaining = credits_remaining + p_amount,
      updated_at = NOW()
  WHERE id = p_user_id;
END;
$$;

-- Atomically increment the total estimates generated counter on a profile row.
CREATE OR REPLACE FUNCTION increment_estimates_generated(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE profiles
  SET total_estimates_generated = total_estimates_generated + 1,
      updated_at = NOW()
  WHERE id = p_user_id;
END;
$$;

-- Atomically deduct one credit from a non-subscribed user.
-- Returns TRUE if a credit was successfully deducted, FALSE if no credits remain.
CREATE OR REPLACE FUNCTION deduct_one_credit(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  rows_updated INTEGER;
BEGIN
  UPDATE profiles
  SET credits_remaining = credits_remaining - 1,
      updated_at = NOW()
  WHERE id = p_user_id
    AND credits_remaining > 0
    AND subscription_status <> 'active';
  GET DIAGNOSTICS rows_updated = ROW_COUNT;
  RETURN rows_updated = 1;
END;
$$;
