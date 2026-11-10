-- Stock PostgreSQL CI has no pg_cron. Hosted Supabase does.
do $$
begin
 if exists(select 1 from pg_available_extensions where name='pg_cron') then
  create extension if not exists pg_cron;
  perform cron.schedule('morgan-verified-retention','20 18 * * *','select private.housekeeping()');
 end if;
end $$;
