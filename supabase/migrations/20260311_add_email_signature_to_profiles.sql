-- Add email_signature column to profiles.
-- Stores the contractor's optional closing signature/sign-off text appended
-- to estimate emails sent via the send-estimate-email Edge Function.
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS email_signature TEXT;
