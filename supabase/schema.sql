-- CFMA TASKA prototype schema.
-- Run this in the Supabase SQL editor before using Team Sync.
--
-- Security note:
-- These policies are intentionally permissive for a private prototype using the
-- anon key from a static page. Before public production use, switch to
-- Supabase Auth and replace these policies with authenticated organisation
-- membership checks.

create table if not exists public.timewrap_organizations (
  workspace_id text primary key,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.timewrap_org_users (
  workspace_id text not null references public.timewrap_organizations(workspace_id) on delete cascade,
  user_id text not null,
  user_name text not null,
  email text not null default '',
  role text not null default 'member',
  status text not null default 'active',
  invite_code text,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create table if not exists public.timewrap_snapshots (
  workspace_id text not null references public.timewrap_organizations(workspace_id) on delete cascade,
  user_id text not null,
  user_name text not null,
  state jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

alter table public.timewrap_organizations enable row level security;
alter table public.timewrap_org_users enable row level security;
alter table public.timewrap_snapshots enable row level security;

drop policy if exists "cfma_taska_orgs_select" on public.timewrap_organizations;
drop policy if exists "cfma_taska_orgs_insert" on public.timewrap_organizations;
drop policy if exists "cfma_taska_orgs_update" on public.timewrap_organizations;
drop policy if exists "cfma_taska_users_select" on public.timewrap_org_users;
drop policy if exists "cfma_taska_users_insert" on public.timewrap_org_users;
drop policy if exists "cfma_taska_users_update" on public.timewrap_org_users;
drop policy if exists "cfma_taska_snapshots_select" on public.timewrap_snapshots;
drop policy if exists "cfma_taska_snapshots_insert" on public.timewrap_snapshots;
drop policy if exists "cfma_taska_snapshots_update" on public.timewrap_snapshots;

create policy "cfma_taska_orgs_select"
on public.timewrap_organizations for select
to anon
using (true);

create policy "cfma_taska_orgs_insert"
on public.timewrap_organizations for insert
to anon
with check (true);

create policy "cfma_taska_orgs_update"
on public.timewrap_organizations for update
to anon
using (true)
with check (true);

create policy "cfma_taska_users_select"
on public.timewrap_org_users for select
to anon
using (true);

create policy "cfma_taska_users_insert"
on public.timewrap_org_users for insert
to anon
with check (true);

create policy "cfma_taska_users_update"
on public.timewrap_org_users for update
to anon
using (true)
with check (true);

create policy "cfma_taska_snapshots_select"
on public.timewrap_snapshots for select
to anon
using (true);

create policy "cfma_taska_snapshots_insert"
on public.timewrap_snapshots for insert
to anon
with check (true);

create policy "cfma_taska_snapshots_update"
on public.timewrap_snapshots for update
to anon
using (true)
with check (true);
