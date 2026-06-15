# ☕ AnyPos — Realtime Chat (Supabase)

A WhatsApp‑style realtime chat web app with a **coffee theme**, built on **Supabase**
(Postgres + Auth + Realtime + Storage). Pure HTML/CSS/JS.

> **Upload to GitHub = just `index.html`.** It is fully self‑contained (all CSS &
> JS are inlined), so there are no `css/`/`js/` 404 errors.
>
> **Editing:** the source is `index.src.html` (markup) + `css/` + `js/`. After any
> change run `./build.ps1` to regenerate the inlined `index.html`. Never hand‑edit
> `index.html` — it is generated and will be overwritten.

> Backend is already provisioned on the connected Supabase project
> `ebdvczthxwyhyaqeqvrd`. The schema, RLS policies, storage buckets and realtime
> are live. You only need to enable social login (optional) and serve the files.

## ✨ Features

| # | Feature | Status |
|---|---------|--------|
| 1 | Coffee‑themed WhatsApp‑style 3‑column UI | ✅ |
| 2 | Unique numeric **ID** + **username** per user, search by either | ✅ |
| 3 | Add friend → accept → friends; friend badge (☕) on profiles | ✅ |
| 4 | Chat list of everyone you've messaged (friends marked) | ✅ |
| 5 | Email/password + **Google** login, persistent session | ✅ (Google needs 1 dashboard step) |
| 6 | Settings: themes, fonts, avatars (+upload), borders — free & **PRO** | ✅ |
| 7 | **Developer console** (ID 1): grant/revoke PRO with expiry, ban, monitor chats & activity | ✅ |
| 8 | Groups, communities & channels | ✅ |
| 9 | No re‑login on refresh | ✅ |
| 10 | Send photos / videos / files / links, full‑quality, downloadable | ✅ |
| 11 | Delete for me / delete for everyone (long‑press a message) | ✅ |
| 12 | Security: RLS on every table, server‑enforced privileges | ✅ |

## ⚠️ One required setup step (2 clicks)

By default this Supabase project has **"Confirm email" ON**, so email/password
sign‑ups can't log in until they click a confirmation email. For a smooth
experience, turn it off:

> Supabase Dashboard → **Authentication → Providers → Email** →
> turn **"Confirm email" OFF** → Save.

(Leave it on if you prefer requiring email verification — then users must confirm
before their first login.)

## 🚀 Run locally

You must serve over HTTP (not `file://`) so Supabase auth + storage work.

```powershell
# from this folder
./serve.ps1            # then open http://localhost:5500
```
or any static server, e.g. `npx serve` / VS Code "Live Server".

## 👑 Developer account (ID 1)

The **first account that registers becomes the developer** (user ID 1) and is
permanently PRO. Register your own account first — you'll get the 🛠️ Developer
tab in the left rail with:
- Grant / revoke PRO (permanent, 1 week, 1 month, 1 year auto‑expiry)
- Ban / unban accounts
- Monitor recent messages across all conversations + activity log

## 🔐 Enable Google login (optional, ~2 min)

1. Supabase Dashboard → **Authentication → Providers → Google** → enable.
2. Add your Google OAuth Client ID & secret
   (Google Cloud Console → Credentials → OAuth client → Web).
3. In Google Cloud, add the authorized redirect URI shown by Supabase
   (`https://ebdvczthxwyhyaqeqvrd.supabase.co/auth/v1/callback`).
4. Supabase → **Authentication → URL Configuration** → add your site URL
   (e.g. `http://localhost:5500` and your GitHub Pages URL) to *Redirect URLs*.

Email/password works out of the box (email confirmation can be turned off under
Authentication → Providers → Email for instant sign‑in).

## 🗄️ Database

Full schema is documented in [`schema.sql`](schema.sql) for reference — it has
already been applied. Tables: `profiles`, `friendships`, `conversations`,
`conversation_members`, `messages`, `message_deletions`, `activity_log`.

## 🔑 Keys & security

- `js/config.js` contains only the **public anon key** — safe to commit. RLS
  ensures users can only read/write their own data.
- The `service_role` / secret key is **never** in this repo. Keep it private.
- "Developer can read all chats" means messages are **not** end‑to‑end encrypted
  by design (per requirement #6). Anyone with database admin access can read them.

## 📦 Deploy to GitHub Pages

Push this `coffee-chat/` folder to a repo and enable Pages (root or `/docs`).
Remember to add the Pages URL to Supabase **Redirect URLs** for Google login.
