-- delete_account RPC
-- Called by the authenticated user from the app to permanently remove their
-- own account data.  SECURITY DEFINER is required so the function can DELETE
-- from auth.users (which is not accessible to the normal anon/authenticated
-- roles).
--
-- Execution order:
--   1. Delete estimates (FK to profiles ON DELETE CASCADE would handle this
--      automatically when the profile is removed, but we do it explicitly so
--      the function is readable and predictable).
--   2. Delete the profile row.
--   3. Delete the auth.users row — this terminates the session and invalidates
--      all JWTs issued for the user.

CREATE OR REPLACE FUNCTION delete_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Guard: only allow authenticated callers to delete their own account.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- 1. Remove all estimates belonging to this user.
  DELETE FROM estimates WHERE user_id = auth.uid();

  -- 2. Remove the profile row.
  DELETE FROM profiles WHERE id = auth.uid();

  -- 3. Remove the auth user record.  This must come last because the previous
  --    steps rely on auth.uid() still resolving within the same transaction.
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$;
