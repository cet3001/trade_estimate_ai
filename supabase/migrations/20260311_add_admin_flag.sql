-- Add is_admin flag to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT FALSE;

-- Auto-set is_admin = TRUE for cet3001@gmail.com whenever they sign in / profile is created.
-- Uses a function that joins profiles to auth.users by email.
CREATE OR REPLACE FUNCTION set_admin_for_known_emails()
RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = NEW.id AND email = 'cet3001@gmail.com'
  ) THEN
    NEW.is_admin := TRUE;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fire before insert or update on profiles
DROP TRIGGER IF EXISTS trg_set_admin ON profiles;
CREATE TRIGGER trg_set_admin
  BEFORE INSERT OR UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION set_admin_for_known_emails();

-- Backfill: if the profile already exists, set is_admin now
UPDATE profiles
SET is_admin = TRUE
WHERE id IN (
  SELECT id FROM auth.users WHERE email = 'cet3001@gmail.com'
);
