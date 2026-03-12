-- Device session tracking for concurrent session limiting.
-- One active device per user: the device with the most-recent last_seen is the
-- authoritative session. Calling register-device updates last_seen; any other
-- device that subsequently calls check-device-session will receive valid=false.

CREATE TABLE IF NOT EXISTS device_sessions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_id   TEXT NOT NULL,
  device_name TEXT,
  last_seen   TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, device_id)
);

ALTER TABLE device_sessions ENABLE ROW LEVEL SECURITY;

-- Users can only access their own device sessions.
CREATE POLICY "Users manage own device sessions"
  ON device_sessions
  FOR ALL
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
