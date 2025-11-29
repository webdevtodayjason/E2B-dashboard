-- Add team_limits table required by dashboard
CREATE TABLE IF NOT EXISTS public.team_limits (
  id UUID PRIMARY KEY REFERENCES public.teams(id) ON DELETE CASCADE,
  concurrent_sandboxes INTEGER NOT NULL DEFAULT 0,
  disk_mb INTEGER NOT NULL DEFAULT 0,
  max_length_hours INTEGER NOT NULL DEFAULT 0,
  max_ram_mb INTEGER NOT NULL DEFAULT 0,
  max_vcpu INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.team_limits ENABLE ROW LEVEL SECURITY;

-- Admin-only RLS (service_role bypasses RLS; keep minimal policy for safety)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = public AND tablename = team_limits AND policyname = read_write_admin_only
  ) THEN
    CREATE POLICY read_write_admin_only ON public.team_limits
      FOR ALL
      USING (auth.role() = service_role)
      WITH CHECK (auth.role() = service_role);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS team_limits_id_idx ON public.team_limits(id);
