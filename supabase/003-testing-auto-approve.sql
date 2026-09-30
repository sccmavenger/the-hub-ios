-- =============================================================================
-- 003 — TESTING ONLY: auto-approve coach sign-ups.
--
-- ⚠️ REMOVE BEFORE LAUNCH. When real approvals are wired in (admin review +
-- Resend notification emails), run:
--   drop trigger if exists trg_auto_approve_coach on public.coach_requests;
--   drop function if exists public.auto_approve_coach_request();
-- =============================================================================

create or replace function public.auto_approve_coach_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_roles (user_id, role)
  values (new.user_id, 'coach')
  on conflict (user_id, role) do nothing;

  new.status := 'approved';
  new.reviewed_at := now();
  return new;
end;
$$;

revoke all on function public.auto_approve_coach_request() from public, anon, authenticated;

drop trigger if exists trg_auto_approve_coach on public.coach_requests;
create trigger trg_auto_approve_coach
before insert on public.coach_requests
for each row execute function public.auto_approve_coach_request();

-- Approve anyone already stuck in pending (e.g. accounts created before this)
insert into public.user_roles (user_id, role)
select user_id, 'coach' from public.coach_requests where status = 'pending'
on conflict (user_id, role) do nothing;

update public.coach_requests
set status = 'approved', reviewed_at = now()
where status = 'pending';
