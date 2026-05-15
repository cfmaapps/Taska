-- CFMA TASKA prototype schema.
-- Run this in the Supabase SQL editor before using Team Sync.
--
-- Security note:
-- These policies are intentionally permissive for a private prototype using the
-- anon key from a static page. Before public production use, switch to
-- Supabase Auth and replace these policies with authenticated organisation
-- membership checks.

create extension if not exists pgcrypto;

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

create table if not exists public.timewrap_user_logins (
  workspace_id text not null references public.timewrap_organizations(workspace_id) on delete cascade,
  user_id text not null,
  username text not null,
  user_name text not null,
  email text not null default '',
  password_hash text not null,
  role text not null default 'member',
  status text not null default 'active',
  created_by text,
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (workspace_id, user_id),
  unique (workspace_id, username)
);

create table if not exists public.timewrap_login_sessions (
  workspace_id text not null,
  user_id text not null,
  session_hash text primary key,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  foreign key (workspace_id, user_id)
    references public.timewrap_user_logins(workspace_id, user_id)
    on delete cascade
);

alter table public.timewrap_organizations enable row level security;
alter table public.timewrap_org_users enable row level security;
alter table public.timewrap_snapshots enable row level security;
alter table public.timewrap_user_logins enable row level security;
alter table public.timewrap_login_sessions enable row level security;

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

create or replace function public.cfma_taska_hash_token(p_token text)
returns text
language sql
security definer
set search_path = public, extensions
as $$
  select encode(digest(coalesce(p_token, ''), 'sha256'), 'hex');
$$;

create or replace function public.cfma_taska_bootstrap_owner(
  p_workspace_id text,
  p_username text,
  p_password text,
  p_user_name text default 'Lachlan'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_workspace text := lower(trim(coalesce(p_workspace_id, 'cfma')));
  v_username text := lower(trim(coalesce(p_username, '')));
  v_user_name text := nullif(trim(coalesce(p_user_name, '')), '');
  v_user_id text := gen_random_uuid()::text;
begin
  if v_workspace = '' then
    v_workspace := 'cfma';
  end if;
  if v_username = '' or coalesce(p_password, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'Username and password are required.');
  end if;
  if length(p_password) < 8 then
    return jsonb_build_object('ok', false, 'error', 'Password must be at least 8 characters.');
  end if;
  if exists (select 1 from public.timewrap_user_logins where workspace_id = v_workspace) then
    return jsonb_build_object('ok', false, 'error', 'An owner login already exists for this workspace.');
  end if;
  if v_user_name is null then
    v_user_name := v_username;
  end if;

  insert into public.timewrap_organizations (workspace_id, name, updated_at)
  values (v_workspace, v_workspace, now())
  on conflict (workspace_id) do update set updated_at = excluded.updated_at;

  insert into public.timewrap_org_users (
    workspace_id, user_id, user_name, email, role, status, created_by, updated_at
  ) values (
    v_workspace, v_user_id, v_user_name, '', 'owner', 'active', v_user_id, now()
  );

  insert into public.timewrap_user_logins (
    workspace_id, user_id, username, user_name, email, password_hash, role, status, created_by, updated_at
  ) values (
    v_workspace, v_user_id, v_username, v_user_name, '', crypt(p_password, gen_salt('bf')), 'owner', 'active', v_user_id, now()
  );

  return jsonb_build_object(
    'ok', true,
    'workspaceId', v_workspace,
    'userId', v_user_id,
    'username', v_username,
    'userName', v_user_name,
    'role', 'owner'
  );
end;
$$;

create or replace function public.cfma_taska_login(
  p_workspace_id text,
  p_username text,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_workspace text := lower(trim(coalesce(p_workspace_id, 'cfma')));
  v_username text := lower(trim(coalesce(p_username, '')));
  v_login public.timewrap_user_logins%rowtype;
  v_token text := encode(gen_random_bytes(32), 'hex');
  v_session_hash text := public.cfma_taska_hash_token(v_token);
begin
  if v_workspace = '' then
    v_workspace := 'cfma';
  end if;

  select *
  into v_login
  from public.timewrap_user_logins
  where workspace_id = v_workspace
    and username = v_username
    and status = 'active'
  limit 1;

  if not found or v_login.password_hash <> crypt(coalesce(p_password, ''), v_login.password_hash) then
    return jsonb_build_object('ok', false, 'error', 'Invalid username or password.');
  end if;

  delete from public.timewrap_login_sessions where expires_at < now();

  insert into public.timewrap_login_sessions (workspace_id, user_id, session_hash, expires_at)
  values (v_login.workspace_id, v_login.user_id, v_session_hash, now() + interval '30 days');

  update public.timewrap_user_logins
  set last_login_at = now(), updated_at = now()
  where workspace_id = v_login.workspace_id and user_id = v_login.user_id;

  insert into public.timewrap_org_users (
    workspace_id, user_id, user_name, email, role, status, updated_at
  ) values (
    v_login.workspace_id, v_login.user_id, v_login.user_name, v_login.email, v_login.role, v_login.status, now()
  )
  on conflict (workspace_id, user_id) do update
  set user_name = excluded.user_name,
      email = excluded.email,
      role = excluded.role,
      status = excluded.status,
      updated_at = excluded.updated_at;

  return jsonb_build_object(
    'ok', true,
    'sessionToken', v_token,
    'workspaceId', v_login.workspace_id,
    'userId', v_login.user_id,
    'username', v_login.username,
    'userName', v_login.user_name,
    'role', v_login.role
  );
end;
$$;

create or replace function public.cfma_taska_current_user(
  p_workspace_id text,
  p_session_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_workspace text := lower(trim(coalesce(p_workspace_id, 'cfma')));
  v_login public.timewrap_user_logins%rowtype;
begin
  if v_workspace = '' then
    v_workspace := 'cfma';
  end if;

  select l.*
  into v_login
  from public.timewrap_login_sessions s
  join public.timewrap_user_logins l
    on l.workspace_id = s.workspace_id
   and l.user_id = s.user_id
  where s.workspace_id = v_workspace
    and s.session_hash = public.cfma_taska_hash_token(p_session_token)
    and s.expires_at > now()
    and l.status = 'active'
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Session expired.');
  end if;

  update public.timewrap_login_sessions
  set expires_at = now() + interval '30 days'
  where session_hash = public.cfma_taska_hash_token(p_session_token);

  return jsonb_build_object(
    'ok', true,
    'workspaceId', v_login.workspace_id,
    'userId', v_login.user_id,
    'username', v_login.username,
    'userName', v_login.user_name,
    'role', v_login.role
  );
end;
$$;

create or replace function public.cfma_taska_create_login(
  p_workspace_id text,
  p_session_token text,
  p_username text,
  p_password text,
  p_user_name text,
  p_email text default '',
  p_role text default 'member'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_workspace text := lower(trim(coalesce(p_workspace_id, 'cfma')));
  v_username text := lower(trim(coalesce(p_username, '')));
  v_user_name text := nullif(trim(coalesce(p_user_name, '')), '');
  v_email text := trim(coalesce(p_email, ''));
  v_role text := lower(trim(coalesce(p_role, 'member')));
  v_creator public.timewrap_user_logins%rowtype;
  v_user_id text := gen_random_uuid()::text;
begin
  if v_workspace = '' then
    v_workspace := 'cfma';
  end if;
  if v_role not in ('owner', 'admin', 'member') then
    v_role := 'member';
  end if;

  select l.*
  into v_creator
  from public.timewrap_login_sessions s
  join public.timewrap_user_logins l
    on l.workspace_id = s.workspace_id
   and l.user_id = s.user_id
  where s.workspace_id = v_workspace
    and s.session_hash = public.cfma_taska_hash_token(p_session_token)
    and s.expires_at > now()
    and l.status = 'active'
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Sign in again before creating users.');
  end if;
  if v_creator.role not in ('owner', 'admin') then
    return jsonb_build_object('ok', false, 'error', 'Only owners or admins can create logins.');
  end if;
  if v_creator.role = 'admin' and v_role = 'owner' then
    v_role := 'admin';
  end if;
  if v_username = '' or v_user_name is null or coalesce(p_password, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'Name, username, and password are required.');
  end if;
  if length(p_password) < 8 then
    return jsonb_build_object('ok', false, 'error', 'Password must be at least 8 characters.');
  end if;
  if exists (select 1 from public.timewrap_user_logins where workspace_id = v_workspace and username = v_username) then
    return jsonb_build_object('ok', false, 'error', 'That username already exists.');
  end if;

  insert into public.timewrap_org_users (
    workspace_id, user_id, user_name, email, role, status, created_by, updated_at
  ) values (
    v_workspace, v_user_id, v_user_name, v_email, v_role, 'active', v_creator.user_id, now()
  );

  insert into public.timewrap_user_logins (
    workspace_id, user_id, username, user_name, email, password_hash, role, status, created_by, updated_at
  ) values (
    v_workspace, v_user_id, v_username, v_user_name, v_email, crypt(p_password, gen_salt('bf')), v_role, 'active', v_creator.user_id, now()
  );

  return jsonb_build_object(
    'ok', true,
    'workspaceId', v_workspace,
    'userId', v_user_id,
    'username', v_username,
    'userName', v_user_name,
    'role', v_role
  );
end;
$$;

create or replace function public.cfma_taska_logout(
  p_workspace_id text,
  p_session_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_workspace text := lower(trim(coalesce(p_workspace_id, 'cfma')));
begin
  if v_workspace = '' then
    v_workspace := 'cfma';
  end if;

  delete from public.timewrap_login_sessions
  where workspace_id = v_workspace
    and session_hash = public.cfma_taska_hash_token(p_session_token);

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.cfma_taska_bootstrap_owner(text, text, text, text) to anon, authenticated;
grant execute on function public.cfma_taska_login(text, text, text) to anon, authenticated;
grant execute on function public.cfma_taska_current_user(text, text) to anon, authenticated;
grant execute on function public.cfma_taska_create_login(text, text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.cfma_taska_logout(text, text) to anon, authenticated;
