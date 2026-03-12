-- Teams: team owner and plan metadata
CREATE TABLE IF NOT EXISTS teams (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id                UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name                    TEXT NOT NULL,
  subscription_product_id TEXT NOT NULL,
  seat_limit              INT  NOT NULL DEFAULT 3,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Team membership (includes pending invitations)
CREATE TABLE IF NOT EXISTS team_members (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id    UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  user_id    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  email      TEXT NOT NULL,
  role       TEXT NOT NULL DEFAULT 'member',   -- 'owner' | 'member'
  status     TEXT NOT NULL DEFAULT 'pending',  -- 'pending' | 'active'
  invited_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  joined_at  TIMESTAMPTZ,
  UNIQUE (team_id, email)
);

-- Link profiles to their team
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS team_id   UUID REFERENCES teams(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS team_role TEXT;

-- RLS: teams
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Team owners manage their team"
  ON teams FOR ALL
  USING  (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Team members view their team"
  ON teams FOR SELECT
  USING (
    id IN (
      SELECT team_id FROM profiles
      WHERE id = auth.uid() AND team_id IS NOT NULL
    )
  );

-- RLS: team_members
ALTER TABLE team_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Team owners manage members"
  ON team_members FOR ALL
  USING  (team_id IN (SELECT id FROM teams WHERE owner_id = auth.uid()))
  WITH CHECK (team_id IN (SELECT id FROM teams WHERE owner_id = auth.uid()));

CREATE POLICY "Members view own membership"
  ON team_members FOR SELECT
  USING (user_id = auth.uid());

-- RPC: returns true if uid has team access (owner or active member)
CREATE OR REPLACE FUNCTION has_team_access(uid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = uid
      AND p.team_id IS NOT NULL
      AND (
        EXISTS (
          SELECT 1 FROM teams t
          WHERE t.id = p.team_id AND t.owner_id = uid
        )
        OR
        EXISTS (
          SELECT 1 FROM team_members tm
          WHERE tm.team_id = p.team_id
            AND tm.user_id = uid
            AND tm.status = 'active'
        )
      )
  );
END;
$$;

-- Trigger: auto-join team when profile is created if email matches a pending invite
CREATE OR REPLACE FUNCTION auto_join_team_on_signup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_team_id UUID;
BEGIN
  SELECT team_id INTO v_team_id
  FROM team_members
  WHERE email  = NEW.email
    AND status = 'pending'
    AND user_id IS NULL
  LIMIT 1;

  IF v_team_id IS NOT NULL THEN
    UPDATE team_members
    SET    user_id   = NEW.id,
           status    = 'active',
           joined_at = now()
    WHERE  team_id   = v_team_id
      AND  email     = NEW.email
      AND  status    = 'pending';

    NEW.team_id   := v_team_id;
    NEW.team_role := 'member';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auto_join_team
  BEFORE INSERT ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION auto_join_team_on_signup();
