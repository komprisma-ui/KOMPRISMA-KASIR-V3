-- Isolate legacy VORA tables and RPCs after the database was repurposed for KASIRA.
-- No VORA table rows were found during the audit; schema is retained for rollback,
-- but client roles can no longer read or mutate it through the Data API.
do $$
declare r record;
begin
  for r in
    select c.oid::regclass as relation_name
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind in ('r','p') and c.relname like 'vora\_%' escape '\'
  loop
    execute format('revoke all on table %s from public, anon, authenticated', r.relation_name);
    execute format('grant all on table %s to service_role', r.relation_name);
  end loop;
  for r in
    select p.oid::regprocedure as function_name
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'vora\_%' escape '\'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.function_name);
    execute format('grant execute on function %s to service_role', r.function_name);
  end loop;
end $$;
