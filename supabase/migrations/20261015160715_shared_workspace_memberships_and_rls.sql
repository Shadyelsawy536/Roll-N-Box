create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table if not exists public.workspace_memberships (
  user_id uuid primary key references auth.users(id) on delete cascade,
  workspace_owner_id uuid not null references auth.users(id) on delete cascade,
  invited_by uuid references auth.users(id) on delete set null,
  invited_email text,
  created_at timestamptz not null default now(),
  constraint workspace_memberships_not_self check (user_id = workspace_owner_id or invited_by is not null)
);
alter table public.workspace_memberships enable row level security;
revoke all on public.workspace_memberships from anon;
grant select on public.workspace_memberships to authenticated;
drop policy if exists workspace_memberships_read_self on public.workspace_memberships;
create policy workspace_memberships_read_self on public.workspace_memberships
  for select to authenticated using (user_id = (select auth.uid()));

insert into public.workspace_memberships (user_id, workspace_owner_id, invited_by, invited_email)
select id, id, id, email from auth.users
where id = '39ee9ce4-4f70-4a4a-8a7e-ab65f7e4463c'::uuid
on conflict (user_id) do nothing;

create or replace function private.current_workspace_owner_id()
returns uuid language sql stable security definer set search_path = ''
as $function$
  select wm.workspace_owner_id from public.workspace_memberships as wm
  where wm.user_id = auth.uid() limit 1
$function$;
revoke all on function private.current_workspace_owner_id() from public, anon;
grant execute on function private.current_workspace_owner_id() to authenticated;

do $migration$
declare r record; v_definition text;
begin
  for r in
    select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosrc ilike '%auth.uid%'
  loop
    v_definition := pg_get_functiondef(r.oid);
    v_definition := replace(v_definition, 'auth.uid()', 'private.current_workspace_owner_id()');
    execute v_definition;
  end loop;

  for r in
    select c.table_schema, c.table_name from information_schema.columns c
    join information_schema.tables t on t.table_schema=c.table_schema and t.table_name=c.table_name
    where c.table_schema='public' and c.column_name='owner_id'
      and c.column_default is not null and t.table_type='BASE TABLE'
  loop
    execute format('alter table %I.%I alter column owner_id set default private.current_workspace_owner_id()', r.table_schema, r.table_name);
  end loop;

  for r in select distinct schemaname, tablename from pg_policies where schemaname='public'
  loop
    for v_definition in select policyname from pg_policies where schemaname=r.schemaname and tablename=r.tablename
    loop
      execute format('drop policy if exists %I on %I.%I', v_definition, r.schemaname, r.tablename);
    end loop;
  end loop;

  for r in
    select c.table_name from information_schema.columns c
    join information_schema.tables t on t.table_schema=c.table_schema and t.table_name=c.table_name
    where c.table_schema='public' and c.column_name='owner_id' and t.table_type='BASE TABLE'
  loop
    if r.table_name in ('sales_returns','sales_return_items','purchase_returns','purchase_return_items') then
      execute format('create policy workspace_select on public.%I for select to authenticated using (owner_id = private.current_workspace_owner_id())', r.table_name);
      execute format('create policy workspace_insert on public.%I for insert to authenticated with check (owner_id = private.current_workspace_owner_id())', r.table_name);
    else
      execute format('create policy workspace_all on public.%I for all to authenticated using (owner_id = private.current_workspace_owner_id()) with check (owner_id = private.current_workspace_owner_id())', r.table_name);
    end if;
  end loop;
end
$migration$;
