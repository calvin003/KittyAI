-- ============================================================================
-- Tables for the website's Windows waitlist + contact form.
-- Run this in the Supabase SQL editor (same project as the proxy).
--
-- Both allow ANONYMOUS inserts (so visitors can submit without logging in)
-- using your publishable key, but NOBODY can read the rows via the API — only
-- you, in the Supabase dashboard. So emails/messages stay private.
-- ============================================================================

create table if not exists public.waitlist (
  id         bigint generated always as identity primary key,
  email      text not null,
  platform   text default 'windows',
  created_at timestamptz not null default now()
);

create table if not exists public.contact_messages (
  id         bigint generated always as identity primary key,
  name       text,
  email      text,
  message    text not null,
  created_at timestamptz not null default now()
);

alter table public.waitlist          enable row level security;
alter table public.contact_messages  enable row level security;

-- Allow inserts from anyone (anon + signed-in). No SELECT policy is defined,
-- so the data is not readable through the public API.
drop policy if exists "anyone can join waitlist" on public.waitlist;
create policy "anyone can join waitlist"
  on public.waitlist for insert
  to anon, authenticated
  with check (true);

drop policy if exists "anyone can contact" on public.contact_messages;
create policy "anyone can contact"
  on public.contact_messages for insert
  to anon, authenticated
  with check (true);
