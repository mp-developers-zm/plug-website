-- =====================================================================
-- Plug Electronics & More — database setup for Supabase
-- Copyright (c) 2026 M&P Developers. Licensed to Plug Electronics & More.
-- Paste ALL of this into Supabase → SQL Editor → New query → Run. Safe to run again.
-- =====================================================================

-- 1) Tables -------------------------------------------------------------
create table if not exists public.docs (
  collection text not null,
  id         text not null,
  data       jsonb not null default '{}'::jsonb,
  owner      uuid,
  updated_at timestamptz not null default now(),
  primary key (collection, id)
);

create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name    text,
  owner   boolean not null default false,
  added_at timestamptz not null default now()
);

-- 2) Who is an admin? -------------------------------------------------------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- 3) Security rules (Row Level Security) -----------------------------------
alter table public.docs   enable row level security;
alter table public.admins enable row level security;

-- Let the website reach the tables (the rules below still decide what each person may do).
grant usage on schema public to anon, authenticated;
grant select on public.docs to anon, authenticated;
grant insert, update, delete on public.docs to authenticated;
grant select on public.admins to authenticated;
grant execute on function public.is_admin() to anon, authenticated;

drop policy if exists "read public store data" on public.docs;
drop policy if exists "admins do everything"   on public.docs;
drop policy if exists "customers add own"      on public.docs;
drop policy if exists "customers update own"   on public.docs;
drop policy if exists "admins see admins"      on public.admins;

-- Anyone may read the catalogue, discount codes, store settings and order status.
-- A customer may also read their own orders / newsletter sign-up.
create policy "read public store data" on public.docs for select
  using (collection in ('products','codes','config','orderstatus') or owner = auth.uid() or public.is_admin());

-- Staff (admins) can create, change and delete anything.
create policy "admins do everything" on public.docs for all
  using (public.is_admin()) with check (public.is_admin());

-- A visitor can only write their OWN order list and newsletter sign-up.
create policy "customers add own" on public.docs for insert
  with check (collection in ('orders','subscribers') and id = auth.uid()::text and owner = auth.uid());
create policy "customers update own" on public.docs for update
  using (collection in ('orders','subscribers') and owner = auth.uid())
  with check (collection in ('orders','subscribers') and id = auth.uid()::text and owner = auth.uid());

-- Signed-in staff can see the admin list (to know their own role).
create policy "admins see admins" on public.admins for select
  using (user_id = auth.uid() or public.is_admin());

-- 4) Live updates -------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.docs;
exception when duplicate_object then null; when undefined_object then null; end $$;

-- 5) Product photo storage -----------------------------------------------------
insert into storage.buckets (id, name, public) values ('product-images','product-images', true)
on conflict (id) do nothing;
drop policy if exists "admins upload images" on storage.objects;
drop policy if exists "admins change images" on storage.objects;
drop policy if exists "admins delete images" on storage.objects;
create policy "admins upload images" on storage.objects for insert with check (bucket_id = 'product-images' and public.is_admin());
create policy "admins change images" on storage.objects for update using (bucket_id = 'product-images' and public.is_admin());
create policy "admins delete images" on storage.objects for delete using (bucket_id = 'product-images' and public.is_admin());

-- 6) Starting data: 23 products, 2 discount codes, store settings -----------------
insert into public.docs (collection, id, data) values
  ('products','duo','{"n": "iPhone Duo", "sp": "256GB", "p": 68000, "was": 0, "img": "duo2", "c": "iphone", "b": "New", "stock": "in", "featured": true, "order": 0}'::jsonb),
  ('products','ip18pm','{"n": "iPhone 18 Pro Max", "sp": "256GB", "p": 38500, "was": 0, "img": "ip18pm", "c": "iphone", "b": "New", "stock": "in", "featured": true, "order": 1}'::jsonb),
  ('products','fold7','{"n": "Samsung Galaxy Z Fold7", "sp": "256GB", "p": 29000, "was": 0, "img": "fold7", "c": "samsung", "b": "", "stock": "in", "featured": true, "order": 2}'::jsonb),
  ('products','ip17pm','{"n": "iPhone 17 Pro Max", "sp": "256GB", "p": 27999, "was": 0, "img": "ip17pm", "c": "iphone", "b": "Popular", "stock": "in", "featured": false, "order": 3}'::jsonb),
  ('products','s26u','{"n": "Samsung Galaxy S26 Ultra", "sp": "256GB", "p": 25000, "was": 0, "img": "s26u", "c": "samsung", "b": "New", "stock": "in", "featured": true, "order": 4}'::jsonb),
  ('products','hp14','{"n": "HP Pavilion 14th Gen", "sp": "Intel Core i5 · 512GB SSD · 16GB RAM", "p": 24500, "was": 0, "img": "hp14", "c": "laptops", "b": "Brand new", "stock": "in", "featured": false, "order": 5}'::jsonb),
  ('products','victus','{"n": "HP Victus 15.6\"", "sp": "Core i5 13th Gen · 1TB SSD · 16GB RAM · RTX 2050 4GB", "p": 22000, "was": 0, "img": "victus", "c": "laptops", "b": "Brand new", "stock": "in", "featured": true, "order": 6}'::jsonb),
  ('products','ip17air','{"n": "iPhone 17 Air", "sp": "256GB", "p": 21500, "was": 0, "img": "ip17air", "c": "iphone", "b": "", "stock": "in", "featured": true, "order": 7}'::jsonb),
  ('products','s25u','{"n": "Samsung Galaxy S25 Ultra", "sp": "256GB", "p": 20000, "was": 0, "img": "s25u", "c": "samsung", "b": "", "stock": "in", "featured": false, "order": 8}'::jsonb),
  ('products','ps5','{"n": "PlayStation 5", "sp": "Gaming console", "p": 15500, "was": 0, "img": "ps5", "c": "consoles", "b": "", "stock": "in", "featured": true, "order": 9}'::jsonb),
  ('products','switch2','{"n": "Nintendo Switch 2", "sp": "256GB", "p": 13999, "was": 0, "img": "switch2", "c": "consoles", "b": "New", "stock": "in", "featured": true, "order": 10}'::jsonb),
  ('products','ip14pm','{"n": "iPhone 14 Pro Max", "sp": "256GB", "p": 13500, "was": 0, "img": "ip14pm", "c": "iphone", "b": "", "stock": "in", "featured": false, "order": 11}'::jsonb),
  ('products','ipad11','{"n": "iPad 11th Gen (A16)", "sp": "Wi-Fi · 128GB", "p": 11000, "was": 0, "img": "ipad11", "c": "tablets", "b": "", "stock": "in", "featured": true, "order": 12}'::jsonb),
  ('products','a57','{"n": "Samsung Galaxy A57", "sp": "256GB", "p": 10500, "was": 0, "img": "a57", "c": "samsung", "b": "", "stock": "in", "featured": false, "order": 13}'::jsonb),
  ('products','iphone13','{"n": "iPhone 13", "sp": "128GB", "p": 7000, "was": 0, "img": "iphone13", "c": "iphone", "b": "", "stock": "in", "featured": false, "order": 14}'::jsonb),
  ('products','s22','{"n": "Samsung Galaxy S22", "sp": "256GB", "p": 7000, "was": 0, "img": "s22", "c": "samsung", "b": "", "stock": "in", "featured": false, "order": 15}'::jsonb),
  ('products','a26','{"n": "Samsung Galaxy A26", "sp": "128GB", "p": 6000, "was": 0, "img": "a26", "c": "samsung", "b": "", "stock": "in", "featured": false, "order": 16}'::jsonb),
  ('products','taba11','{"n": "Samsung Galaxy Tab A11", "sp": "64GB", "p": 5000, "was": 0, "img": "taba11", "c": "tablets", "b": "", "stock": "in", "featured": false, "order": 17}'::jsonb),
  ('products','a17','{"n": "Samsung Galaxy A17", "sp": "128GB", "p": 4500, "was": 0, "img": "a17", "c": "samsung", "b": "", "stock": "in", "featured": false, "order": 18}'::jsonb),
  ('products','a16','{"n": "Samsung Galaxy A16", "sp": "128GB", "p": 4000, "was": 0, "img": "a16", "c": "samsung", "b": "", "stock": "in", "featured": false, "order": 19}'::jsonb),
  ('products','bo6','{"n": "Call of Duty: Black Ops 6", "sp": "PS5 game", "p": 1949.99, "was": 0, "img": "bo6", "c": "games", "b": "", "stock": "in", "featured": true, "order": 20}'::jsonb),
  ('products','codcw','{"n": "Call of Duty: Black Ops Cold War", "sp": "PS4 game", "p": 1800, "was": 0, "img": "codcw", "c": "games", "b": "", "stock": "in", "featured": false, "order": 21}'::jsonb),
  ('products','fc26','{"n": "EA Sports FC 26", "sp": "PS5 game", "p": 1749.99, "was": 0, "img": "fc26", "c": "games", "b": "", "stock": "in", "featured": false, "order": 22}'::jsonb),
  ('codes','WELCOME10','{"type": "pct", "value": 10, "min": 500, "scope": "all", "first": true, "active": true, "expires": ""}'::jsonb),
  ('codes','TECH25','{"type": "pct", "value": 25, "min": 0, "scope": "games", "first": false, "active": true, "expires": ""}'::jsonb),
  ('config','store','{"seeded": true, "wa": "260574541778", "instagram": "https://www.instagram.com/plug_electronics_zm", "facebook": "https://www.facebook.com/share/1CXKEpqzwe/", "pointsPer": 100, "pointValue": 0, "announceOn": false, "announce": "", "freeTowns": "Lusaka & Ndola", "cutoff": 14, "storeName": "Plug Electronics & More", "bfOn": true, "bfDate": "2026-11-27"}'::jsonb)
on conflict (collection, id) do nothing;

-- =====================================================================
-- 7) MAKE YOURSELF ADMIN (run separately, after creating your staff login):
--    Supabase → Authentication → Users → Add user → Create new user
--    (enter your email + a strong password, tick "Auto Confirm User"), then run:
--
--    insert into public.admins (user_id, name, owner)
--    select id, 'Perez', true from auth.users where email = 'YOUR-EMAIL@example.com';
--
--    Add more staff the same way with owner = false.
-- =====================================================================
