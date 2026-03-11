-- Drop the permissive FOR ALL policy
DROP POLICY IF EXISTS "Users manage own profile" ON profiles;

-- Read: users may only see their own row
CREATE POLICY "Users select own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);

-- Insert: users may insert their own row but cannot set is_admin = true
CREATE POLICY "Users insert own profile" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id AND is_admin = FALSE);

-- Update: users may update their own row but is_admin must match the existing DB value
-- (prevents escalation via UPDATE)
CREATE POLICY "Users update own profile" ON profiles
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND is_admin = (SELECT is_admin FROM profiles WHERE id = auth.uid())
  );

-- Delete: users may delete their own row (for account deletion flow)
CREATE POLICY "Users delete own profile" ON profiles
  FOR DELETE USING (auth.uid() = id);
