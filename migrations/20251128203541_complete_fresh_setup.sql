-- ============================================
-- E2B DASHBOARD - COMPLETE FRESH SETUP
-- ============================================
-- This migration creates all tables, functions, triggers, and views from scratch
-- Run this on a fresh database after dropping all existing tables

-- 1. Extensions
CREATE EXTENSION IF NOT EXISTS unaccent;

-- 2. Create teams table
CREATE TABLE public.teams (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  profile_picture_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Create envs table
CREATE TABLE public.envs (
  id TEXT PRIMARY KEY,
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  build_count INTEGER DEFAULT 0,
  spawn_count INTEGER DEFAULT 0,
  public BOOLEAN DEFAULT false,
  cluster_id TEXT,
  created_by UUID,
  last_spawned_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Create users_teams junction table
CREATE TABLE public.users_teams (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member',
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, team_id)
);

-- 5. Create env_defaults table
CREATE TABLE public.env_defaults (
  env_id TEXT PRIMARY KEY REFERENCES public.envs(id) ON DELETE CASCADE,
  description TEXT
);

-- 6. Create indexes
CREATE INDEX envs_team_id_idx ON public.envs(team_id);
CREATE INDEX envs_created_at_idx ON public.envs(created_at);
CREATE INDEX users_teams_user_id_idx ON public.users_teams(user_id);
CREATE INDEX users_teams_team_id_idx ON public.users_teams(team_id);
CREATE INDEX env_defaults_env_id_idx ON public.env_defaults(env_id);

-- 7. Enable Row Level Security
ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.envs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users_teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.env_defaults ENABLE ROW LEVEL SECURITY;

-- 8. Create slug generation function
CREATE OR REPLACE FUNCTION public.generate_team_slug(name TEXT)
RETURNS TEXT AS $$
DECLARE
  base_name TEXT;
BEGIN
  base_name := SPLIT_PART(name, '@', 1);
  RETURN LOWER(
    REGEXP_REPLACE(
      REGEXP_REPLACE(
        UNACCENT(TRIM(base_name)),
        '[^a-zA-Z0-9\s-]',
        '',
        'g'
      ),
      '\s+',
      '-',
      'g'
    )
  );
END;
$$ LANGUAGE plpgsql;

-- 9. Create new user handler function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  team_name TEXT;
  base_slug TEXT;
  final_slug TEXT;
  slug_suffix TEXT;
BEGIN
  -- Get team name
  team_name := COALESCE(
    NEW.raw_user_meta_data->>'full_name',
    SPLIT_PART(NEW.email, '@', 1),
    'Personal Team'
  );
  
  -- Generate slug
  base_slug := public.generate_team_slug(team_name);
  slug_suffix := SUBSTRING(NEW.id::text FROM 1 FOR 8);
  final_slug := base_slug || '-' || slug_suffix;
  
  -- Create team
  INSERT INTO public.teams (id, name, slug, created_at, updated_at)
  VALUES (NEW.id, team_name, final_slug, NOW(), NOW());
  
  -- Add user to team as owner
  INSERT INTO public.users_teams (user_id, team_id, role, is_default)
  VALUES (NEW.id, NEW.id, 'owner', true);
  
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Error creating team for user %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 10. Create trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- 11. Create auth_users view
CREATE OR REPLACE VIEW public.auth_users AS
SELECT id, email FROM auth.users;

REVOKE ALL ON public.auth_users FROM PUBLIC;
REVOKE ALL ON public.auth_users FROM anon;
REVOKE ALL ON public.auth_users FROM authenticated;

-- ============================================
-- SETUP COMPLETE!
-- ============================================
