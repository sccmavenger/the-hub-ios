-- =============================================================================
-- 005 — Notify all admins when a content report is filed (web parity:
-- the web app fans this out in its submitReport server function).
-- =============================================================================

create or replace function public.notify_admins_on_report()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
begin
  for a in select ur.user_id from public.user_roles ur where ur.role = 'admin' loop
    insert into public.notifications (user_id, type, title, body, link)
    values (
      a.user_id,
      'report',
      'New content report',
      'A ' || new.target_type || ' was reported: ' || new.reason,
      '/admin/reports'
    );
  end loop;
  return new;
end;
$$;

revoke all on function public.notify_admins_on_report() from public, anon, authenticated;

drop trigger if exists trg_notify_admins_on_report on public.content_reports;
create trigger trg_notify_admins_on_report
after insert on public.content_reports
for each row execute function public.notify_admins_on_report();
