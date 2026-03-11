-- Fix: Allow admin email to bypass the is_admin = FALSE constraint on INSERT.
-- The trg_set_admin trigger fires BEFORE INSERT and sets is_admin = TRUE for
-- cet3001@gmail.com, so the WITH CHECK clause must permit is_admin = TRUE for that email.
DROP POLICY IF EXISTS "Users insert own profile" ON profiles;

CREATE POLICY "Users insert own profile" ON profiles
  FOR INSERT WITH CHECK (
    auth.uid() = id
    AND (is_admin = FALSE OR auth.email() = 'cet3001@gmail.com')
  );
