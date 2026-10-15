drop policy if exists workspace_memberships_read_self on public.workspace_memberships;
create policy workspace_memberships_read_self on public.workspace_memberships for select to authenticated using (user_id = (select auth.uid()));
