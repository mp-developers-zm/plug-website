# Plug Electronics & More — website

Designed, developed and owned by **M&P Developers**. Licensed (not sold) to Plug Electronics & More. See `LICENSE.txt`.

## What's here

| File | What it is |
|---|---|
| `index.html` | The store: Home, Shop, Deals, Loyalty, Support, Legal |
| `admin.html` | Staff admin: products, prices, discount codes, promotions, email campaigns, orders, settings |
| `config.js` | Where the Supabase keys go |
| `supabase-adapter.js` | Connects the site to the Supabase database |
| `supabase-setup.sql` | Creates the database, security rules and starting data |
| `img/` | Product photos, team photos, category tiles |

## Going live with the database (one time)

1. Create a free account at supabase.com and a **New project** (region: closest to Zambia, e.g. Frankfurt / London).
2. **SQL Editor → New query**: paste all of `supabase-setup.sql` → **Run**.
3. **Authentication → Sign In / Providers**: turn on **Allow anonymous sign-ins** (lets shoppers send orders without an account).
4. **Authentication → Users → Add user**: your staff email + password (tick *Auto Confirm User*). Then in the SQL Editor run:
   ```sql
   insert into public.admins (user_id, name, owner)
   select id, 'Perez', true from auth.users where email = 'YOUR-EMAIL';
   ```
5. **Project Settings → API**: copy the **Project URL** and the **anon public** key into `config.js`.
6. **Authentication → URL Configuration**: set Site URL to the live site address (for password-reset emails).

Admin page: `<site address>/admin.html`.

## Without the database

If `config.js` is empty the site still works: built-in catalogue, cart, WhatsApp ordering. Admin opens in demo mode (changes saved on that device only).

## Custom domain

Buy a domain (e.g. `.co.zm` or `.com`), then in GitHub: **Settings → Pages → Custom domain**, and add the DNS records GitHub shows at your registrar.

Copyright (c) 2026 M&P Developers. All rights reserved.
