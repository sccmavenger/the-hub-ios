-- =============================================================================
-- 007 — Launch hardening. Applied to prod 2026-09-18 by Claude Code during the
-- pre-App-Store-submission security/compliance review (see
-- docs/SUBMISSION-READINESS.md for the full changelog and rationale).
-- Re-runnable.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Remove the TESTING-ONLY coach auto-approval installed by 003.
--    Why: with it live, any anonymous signup instantly became an approved
--    coach with access to published minors' profiles, gated contact info
--    (via bookmarking) and direct messaging. Coach requests are approved
--    manually by admins from now on.
-- ---------------------------------------------------------------------------
drop trigger if exists trg_auto_approve_coach on public.coach_requests;
drop function if exists public.auto_approve_coach_request();

-- ---------------------------------------------------------------------------
-- 2. Server-side, atomic signup. With email confirmation enabled the client
--    has no session immediately after auth.signUp, so it can no longer insert
--    its own user_roles/athletes rows (and the old client-side flow was
--    non-atomic anyway). The iOS app now sends signup_role / full_name /
--    date_of_birth as signup metadata and this trigger creates everything.
--    Coach onboarding stays on the web and is NOT granted any role here.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta_role text := new.raw_user_meta_data ->> 'signup_role';
begin
  insert into public.user_profiles (id, email, display_name)
  values (new.id, new.email, new.raw_user_meta_data ->> 'full_name')
  on conflict (id) do nothing;

  if meta_role in ('athlete', 'parent') then
    insert into public.user_roles (user_id, role)
    values (new.id, meta_role)
    on conflict (user_id, role) do nothing;
  end if;

  if meta_role = 'athlete'
     and coalesce(new.raw_user_meta_data ->> 'full_name', '') <> '' then
    insert into public.athletes (user_id, full_name, date_of_birth, is_published)
    values (
      new.id,
      new.raw_user_meta_data ->> 'full_name',
      nullif(new.raw_user_meta_data ->> 'date_of_birth', '')::date,
      false
    )
    on conflict (user_id) do nothing;
  end if;

  return new;
end;
$$;
-- Trigger on_auth_user_created (setup.sql) already points at this function.

-- ---------------------------------------------------------------------------
-- 3. Guardian consent covers ALL minors. Previously only under-13 athletes
--    with a non-null DOB were gated, so a minor could publish by clearing
--    their date of birth. Now: publishing requires a DOB, and anyone under 18
--    needs recorded guardian consent. (Both currently-published athletes have
--    DOB + consent recorded — verified before deploying.)
-- ---------------------------------------------------------------------------
create or replace function public.enforce_guardian_consent()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.is_published then
    if new.date_of_birth is null then
      raise exception 'A date of birth is required before the profile can be published';
    end if;
    if new.date_of_birth > (current_date - interval '18 years')
       and new.guardian_consent_at is null then
      raise exception 'Athletes under 18 need recorded guardian consent before the profile can be published';
    end if;
  end if;
  return new;
end;
$$;
-- Trigger trg_guardian_consent (002-parity.sql) already points at this function.

-- ---------------------------------------------------------------------------
-- 4. Coaches can only start message threads with PUBLISHED athletes.
--    Athletes/guardians can still reply in their own threads (unchanged).
-- ---------------------------------------------------------------------------
drop policy if exists "messages insert" on public.messages;
create policy "messages insert" on public.messages
  for insert to authenticated
  with check (
    sender_user_id = auth.uid()
    and (
      (coach_user_id = auth.uid()
        and public.has_role('coach')
        and public.athlete_is_published(athlete_id))
      or public.can_manage_athlete(athlete_id)
    )
  );

-- ---------------------------------------------------------------------------
-- 5. Messages are immutable once sent, except read_at. The permissive update
--    policy existed only to support read receipts, but it allowed either
--    party to rewrite message bodies after the fact — unacceptable for
--    adult↔minor messaging where conversations may be evidence in reports.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_message_immutable()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.body is distinct from old.body
     or new.sender_user_id is distinct from old.sender_user_id
     or new.coach_user_id is distinct from old.coach_user_id
     or new.athlete_id is distinct from old.athlete_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Messages cannot be edited after sending';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_message_immutable on public.messages;
create trigger trg_message_immutable
before update on public.messages
for each row execute function public.enforce_message_immutable();

-- ---------------------------------------------------------------------------
-- 6. Coaches can only bookmark PUBLISHED athletes. Bookmarks unlock contact
--    info (002-parity), so an unpublished athlete's UUID must not be
--    pre-bookmarkable. Existing bookmarks stay manageable regardless of
--    publish state (so blocking/unpublishing doesn't strand coach cleanup).
-- ---------------------------------------------------------------------------
drop policy if exists "saved athletes all" on public.coach_saved_athletes;

drop policy if exists "saved athletes select" on public.coach_saved_athletes;
create policy "saved athletes select" on public.coach_saved_athletes
  for select to authenticated
  using (coach_user_id = auth.uid());

drop policy if exists "saved athletes insert" on public.coach_saved_athletes;
create policy "saved athletes insert" on public.coach_saved_athletes
  for insert to authenticated
  with check (
    coach_user_id = auth.uid()
    and public.athlete_is_published(athlete_id)
  );

drop policy if exists "saved athletes update" on public.coach_saved_athletes;
create policy "saved athletes update" on public.coach_saved_athletes
  for update to authenticated
  using (coach_user_id = auth.uid())
  with check (coach_user_id = auth.uid());

drop policy if exists "saved athletes delete" on public.coach_saved_athletes;
create policy "saved athletes delete" on public.coach_saved_athletes
  for delete to authenticated
  using (coach_user_id = auth.uid());
