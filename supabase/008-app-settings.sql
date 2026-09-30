-- =============================================================================
-- 008 — Remote app settings (admin-controlled feature flags).
--
-- Added 2026-09-18 so college crest logos can be switched on/off from the
-- admin portal without shipping an app update. The immediate driver is
-- trademark risk: NCAA/college marks are third-party trademarks we hold no
-- license to, so if a school or its licensing agent sends a takedown we need
-- to stop displaying their mark in minutes, not in an App Review cycle.
--
-- Clients FAIL CLOSED: if the flag can't be read, crests fall back to letter
-- monograms. Default is OFF.
-- Re-runnable.
-- =============================================================================

create table if not exists public.app_settings (
  key text primary key,
  bool_value boolean,
  text_value text,
  description text,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);

alter table public.app_settings enable row level security;

-- Every signed-in client reads flags; only admins can change them.
drop policy if exists "app settings readable" on public.app_settings;
create policy "app settings readable" on public.app_settings
  for select to authenticated
  using (true);

drop policy if exists "admins write app settings" on public.app_settings;
create policy "admins write app settings" on public.app_settings
  for all to authenticated
  using (public.has_role('admin'))
  with check (public.has_role('admin'));

drop trigger if exists set_updated_at on public.app_settings;
create trigger set_updated_at before update on public.app_settings
  for each row execute function public.set_updated_at();

-- Seed the flag OFF. Do NOT overwrite the value if it already exists —
-- re-running this migration must never silently re-enable logos.
insert into public.app_settings (key, bool_value, description)
values (
  'college_logos_enabled',
  false,
  'Show official college crest logos (fetched from public logo sources) instead of letter monograms. Third-party trademarks — keep OFF unless counsel has approved, and switch OFF immediately on any takedown request.'
)
on conflict (key) do nothing;
