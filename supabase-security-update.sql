-- =====================================================================
-- Plug Electronics & More — security update (M&P Developers, 21 Nov 2026)
-- Run ONCE after supabase-setup.sql: Supabase → SQL Editor → New query → paste all → Run.
-- Safe to run again.
-- =====================================================================

-- 0) Only the access the website actually uses ----------------------------------
-- Visitors who are not logged in may only read; logged-in customers (including anonymous
-- shoppers) may write, and the row rules above still decide exactly which rows.
revoke all on public.docs, public.admins from anon, authenticated;
grant select on public.docs to anon, authenticated;
grant insert, update, delete on public.docs to authenticated;
grant select on public.admins to authenticated;

-- 1) New tables start private -------------------------------------------------
-- Without this, any table added later is readable and writable by anyone on the internet
-- until someone remembers to lock it. Each new table must now be granted explicitly, with RLS.
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from anon, authenticated, public;

-- 2) Check prices on new orders in the database --------------------------------
-- The shop computes the cart total in the customer's browser, so an edited request could
-- save an order with a lower price or total. This check runs in the database for every
-- NEW order a customer saves (staff and older orders are not touched) and refuses it when:
--   * an item's price is not the current product price,
--   * a quantity is not a whole number from 1 to 50,
--   * the total is lower than the prices allow (after the largest discount the code could give),
--   * the discount code does not exist or is switched off.
-- Items the database does not know are let through, so checkout never breaks for real customers.
create or replace function public.plug_check_orders() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  o jsonb; it jsonb; prod jsonb; code jsonb;
  old_nos text[] := '{}';
  sub numeric; disc_max numeric; q numeric; known boolean;
begin
  if new.collection <> 'orders' or public.is_admin() then return new; end if;
  if tg_op = 'UPDATE' and old.collection = 'orders' then
    select coalesce(array_agg(x->>'no'), '{}') into old_nos
      from jsonb_array_elements(case when jsonb_typeof(old.data->'list') = 'array' then old.data->'list' else '[]'::jsonb end) x;
  end if;
  if jsonb_typeof(new.data->'list') is distinct from 'array' then return new; end if;

  for o in select * from jsonb_array_elements(new.data->'list') loop
    continue when coalesce(o->>'no', '') = any(old_nos);
    sub := 0; known := true;
    for it in select * from jsonb_array_elements(case when jsonb_typeof(o->'items') = 'array' then o->'items' else '[]'::jsonb end) loop
      q := nullif(it->>'qty', '')::numeric;
      if q is null or q < 1 or q > 50 or q <> trunc(q) then
        raise exception 'Order check failed: a quantity is not allowed. Please refresh the page and try again.';
      end if;
      select data into prod from public.docs where collection = 'products' and id = it->>'id';
      if prod is null then known := false; continue; end if;
      if abs(coalesce(nullif(it->>'price', '')::numeric, -1) - coalesce(nullif(prod->>'p', '')::numeric, 0)) > 0.01 then
        raise exception 'Order check failed: a price has changed. Please refresh the page and try again.';
      end if;
      sub := sub + coalesce(nullif(prod->>'p', '')::numeric, 0) * q;
    end loop;

    disc_max := 0;
    if coalesce(o->>'code', '') <> '' then
      select data into code from public.docs where collection = 'codes' and upper(id) = upper(o->>'code');
      if code is null or coalesce((code->>'active')::boolean, false) = false then
        raise exception 'Order check failed: that discount code is not valid. Please remove it and try again.';
      end if;
      disc_max := case when code->>'type' = 'pct'
                       then sub * least(coalesce(nullif(code->>'value', '')::numeric, 0), 100) / 100
                       else coalesce(nullif(code->>'value', '')::numeric, 0) end;
    end if;

    if known and coalesce(nullif(o->>'total', '')::numeric, -1) < sub - disc_max - 0.01 then
      raise exception 'Order check failed: the total does not match the prices. Please refresh the page and try again.';
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists plug_check_orders on public.docs;
create trigger plug_check_orders before insert or update on public.docs
  for each row when (new.collection = 'orders') execute function public.plug_check_orders();

-- =====================================================================
-- Also do these in the Supabase dashboard (they are settings, not SQL):
--  * Authentication → Sign In / Providers → Email: turn on leaked-password protection (if your plan has it).
--  * Authentication → Rate Limits: keep anonymous sign-ins and emails limited.
--  * Your staff login: turn on MFA (Authentication → Multi-Factor).
--  * Billing: set a spend cap or usage alerts.
-- =====================================================================
