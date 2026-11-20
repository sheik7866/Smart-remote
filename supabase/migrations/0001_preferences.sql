-- Optional accounts (M8). Scope is deliberately tiny: TV nicknames and UI
-- preferences. No client key, token, IP address, MAC address or SSID can be
-- stored here; the guard test in packages/remote_core/test/schema_test.dart
-- fails if a column name implies otherwise.
--
-- Apply with the Supabase CLI (`supabase db push`) against a project you own.
-- Nothing in the app calls this schema yet: the client integration stays out
-- until a project exists to verify two-account isolation against.

create extension if not exists "pgcrypto";

create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  nickname text not null check (char_length(btrim(nickname)) between 1 and 64),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ui_preferences (
  user_id uuid primary key references auth.users (id) on delete cascade,
  theme text not null default 'dark' check (theme in ('dark', 'light', 'system')),
  haptics_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.devices enable row level security;
alter table public.ui_preferences enable row level security;

create policy "devices are owned by the signed-in user"
  on public.devices
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "preferences are owned by the signed-in user"
  on public.ui_preferences
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Signed-out visitors can read nothing, even if a policy is later loosened by
-- mistake: the tables are not granted to anon at all.
revoke all on public.devices from anon;
revoke all on public.ui_preferences from anon;
