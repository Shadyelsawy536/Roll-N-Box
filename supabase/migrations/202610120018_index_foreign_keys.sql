-- Phase 4/5: add indexes for foreign-key columns to reduce lock and query costs.
-- Indexes are created only when no existing index starts with the FK column.
do $$
declare
  fk record;
  idx_name text;
begin
  for fk in
    select ns.nspname as schema_name, tbl.relname as table_name,
           att.attname as column_name, con.conrelid as table_oid,
           att.attnum as attnum
    from pg_constraint con
    join pg_class tbl on tbl.oid = con.conrelid
    join pg_namespace ns on ns.oid = tbl.relnamespace
    join unnest(con.conkey) with ordinality as key_col(attnum, ord) on true
    join pg_attribute att on att.attrelid = tbl.oid and att.attnum = key_col.attnum
    where con.contype = 'f' and ns.nspname = 'public'
  loop
    if not exists (
      select 1 from pg_index ix
      where ix.indrelid = fk.table_oid and ix.indisvalid and ix.indisready
        and ix.indkey[0] = fk.attnum
    ) then
      idx_name := left('idx_fk_' || fk.table_name || '_' || fk.column_name, 50)
                  || '_' || substr(md5(fk.table_name || ':' || fk.column_name), 1, 8);
      execute format('create index if not exists %I on %I.%I (%I)',
        idx_name, fk.schema_name, fk.table_name, fk.column_name);
    end if;
  end loop;
end $$;