-- Enforce tenant ownership at the relational boundary.
-- Existing data was audited before this migration; the checked relationships had no cross-owner rows.
do $$
declare
  r record;
  v_delete text;
  v_update text;
  v_match text;
  v_new_name text;
  v_def text;
begin
  -- Composite unique indexes allow foreign keys to verify both owner and record identity.
  for r in
    select c.oid::regclass as table_name
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r'
      and exists (select 1 from information_schema.columns x where x.table_schema='public' and x.table_name=c.relname and x.column_name='owner_id')
      and exists (select 1 from information_schema.columns x where x.table_schema='public' and x.table_name=c.relname and x.column_name='id')
  loop
    execute format('create unique index if not exists %I on %s (owner_id, id)', 'uq_owner_id_' || replace(r.table_name::text,'.','_'), r.table_name);
  end loop;

  -- Replace single-column public-to-public FKs with owner-scoped composite FKs.
  for r in
    select c.conname, c.conrelid::regclass as source_table,
           sn.nspname as source_schema, st.relname as source_name,
           tn.nspname as target_schema, tt.relname as target_name,
           sa.attname as source_column, ta.attname as target_column,
           c.confdeltype, c.confupdtype, c.confmatchtype,
           c.condeferrable, c.condeferred, c.convalidated
    from pg_constraint c
    join pg_class st on st.oid=c.conrelid
    join pg_namespace sn on sn.oid=st.relnamespace
    join pg_class tt on tt.oid=c.confrelid
    join pg_namespace tn on tn.oid=tt.relnamespace
    join pg_attribute sa on sa.attrelid=st.oid and sa.attnum=c.conkey[1]
    join pg_attribute ta on ta.attrelid=tt.oid and ta.attnum=c.confkey[1]
    where c.contype='f' and sn.nspname='public' and tn.nspname='public'
      and array_length(c.conkey,1)=1 and array_length(c.confkey,1)=1
      and ta.attname='id'
      and exists (select 1 from information_schema.columns x where x.table_schema=sn.nspname and x.table_name=st.relname and x.column_name='owner_id')
      and exists (select 1 from information_schema.columns x where x.table_schema=tn.nspname and x.table_name=tt.relname and x.column_name='owner_id')
  loop
    v_delete := case r.confdeltype when 'a' then 'NO ACTION' when 'r' then 'RESTRICT' when 'c' then 'CASCADE' when 'n' then format('SET NULL (%I)', r.source_column) when 'd' then 'SET DEFAULT' else 'NO ACTION' end;
    v_update := case r.confupdtype when 'a' then 'NO ACTION' when 'r' then 'RESTRICT' when 'c' then 'CASCADE' when 'n' then format('SET NULL (%I)', r.source_column) when 'd' then 'SET DEFAULT' else 'NO ACTION' end;
    v_match := case r.confmatchtype when 'f' then 'FULL' when 'p' then 'PARTIAL' else 'SIMPLE' end;
    v_new_name := left(r.conname, 44) || '_owner_scope';
    execute format('alter table %I.%I drop constraint %I', r.source_schema, r.source_name, r.conname);
    v_def := format(
      'alter table %I.%I add constraint %I foreign key (owner_id, %I) references %I.%I (owner_id, %I) match %s on update %s on delete %s%s%s',
      r.source_schema, r.source_name, v_new_name, r.source_column,
      r.target_schema, r.target_name, r.target_column, v_match, v_update, v_delete,
      case when r.condeferrable then ' deferrable' else ' not deferrable' end,
      case when r.condeferrable and r.condeferred then ' initially deferred' else '' end
    );
    execute v_def;
    if r.convalidated then
      execute format('alter table %I.%I validate constraint %I', r.source_schema, r.source_name, v_new_name);
    end if;
  end loop;
end $$;
