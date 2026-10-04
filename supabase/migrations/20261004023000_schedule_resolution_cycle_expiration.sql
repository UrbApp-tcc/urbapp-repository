-- Expira ciclos vencidos mesmo quando ninguém abre a tela da ocorrência.

create extension if not exists pg_cron with schema pg_catalog;

do $$
declare
  existing_job_id bigint;
begin
  select jobid into existing_job_id
  from cron.job
  where jobname = 'urbapp-expire-resolution-cycles';

  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;

  perform cron.schedule(
    'urbapp-expire-resolution-cycles',
    '*/5 * * * *',
    'select public.expire_resolution_cycles(null);'
  );
end;
$$;
