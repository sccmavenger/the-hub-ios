-- 009: enforce the under-13 signup block server-side (TECH-DEBT #2)
--
-- The app's sign-up UI already refuses athlete signups with a DOB under 13
-- (COPPA posture: a parent/guardian creates and manages the profile instead).
-- Until now that was client-side only — a direct call to /auth/v1/signup
-- with an under-13 date_of_birth would create the account.
--
-- The check lives in handle_new_user, NOT as a constraint on athletes.dob,
-- because under-13 *athlete rows* are legitimate when parent-managed; it is
-- only the child holding their own login that is prohibited.
--
-- Raising here aborts the auth.users insert, so GoTrue returns
-- "Database error saving new user" to the raw-API caller. The in-app flow
-- never reaches this (UI blocks first).

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  meta_role text := new.raw_user_meta_data ->> 'signup_role';
  meta_dob date := nullif(new.raw_user_meta_data ->> 'date_of_birth', '')::date;
begin
  if meta_role = 'athlete'
     and meta_dob is not null
     and meta_dob > (current_date - interval '13 years') then
    raise exception 'athletes under 13 cannot create their own account';
  end if;

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
      meta_dob,
      false
    )
    on conflict (user_id) do nothing;
  end if;

  return new;
end;
$function$;
