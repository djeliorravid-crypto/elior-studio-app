---
name: create-base
description: >
  Scaffold a new high-quality app/website on the proven "base" toolkit —
  the same foundation behind Elior's business app and fitness tracker.
  Gives you an installable PWA + optional native iOS wrapper with: local-first
  storage, resilient Firebase cloud sync (never loses data), daily auto-backup,
  offline support, silent auto-update, dark mode, login + multi-profile lobby,
  export/import, and a polished RTL Hebrew design system. Use this whenever the
  user wants to start a new app or website, or says "צור בסיס" / "create base".
---

# צור בסיס — Create Base

This skill scaffolds a new app from a battle-tested foundation. The user has
already built two real apps on this base (a business manager and a two-person
fitness/nutrition tracker). The goal here is: **give them the same set of tools
for a brand-new app, then customize it to whatever the new app is about.**

## What "the base" includes (the tools we keep)

- **PWA**: installs to the home screen, works offline (`manifest.json` + `sw.js`).
- **Auto-update**: `version.txt` + network-first service worker → users always
  get the latest code, no app-store review. Bump `version.txt` to ship.
- **Local-first storage + cloud sync**: writes hit `localStorage` instantly, then
  a **resilient pending queue** pushes to Firebase Realtime Database. Nothing is
  lost if the network drops or the app closes mid-write. Timestamps merge devices.
- **Daily auto-backup** to a separate Firebase node (keeps 30 days + monthly
  checkpoints) plus a local backup. Restore from cloud or from a JSON file.
- **Login** (simple password) → **Lobby** (pick a profile) → per-profile app.
  Each profile has its own data namespace and accent color. Works for 1 profile
  (lobby auto-skipped) or many.
- **Design system**: RTL Hebrew, light/dark themes via CSS variables, cards,
  bottom-sheet modals, toasts, FAB, sidebar (desktop) + bottom nav (mobile).
- **Export / import** all data as JSON.
- **Native iOS wrapper** (Capacitor) — optional, turns the same code into a real
  iOS app with local notifications.
- **Icon generator** (`make-icons.js`, pure Node, no deps).

The whole app is a **single `index.html`** (HTML + CSS + JS inline). This is
intentional — it is trivial to deploy (GitHub Pages / Cloudflare Pages), easy to
update, and there is no build step.

## How to scaffold a new app

1. **Clarify the new app** (ask the user, ideally with `AskUserQuestion`):
   - What is the app about? (the domain → its data types and pages)
   - One user or several profiles? (names + an emoji/accent each)
   - Cloud sync now (new Firebase project) or local-only for now?
   - App name + a target folder/repo.

2. **Copy the template** from `template/` in this skill folder into the target
   directory: `index.html`, `manifest.json`, `sw.js`, `version.txt`, `_headers`,
   `make-icons.js`, and (if they want native) `native/`.

3. **Customize `index.html`** — everything you change lives near the top, marked
   with `// 👉 CUSTOMIZE`:
   - `APP_NAME`, `PASS` (login password).
   - `PROFILES` — one entry per person, each `{ name, emoji, accent, accent2,
     soft, grad }`. One profile → the lobby is skipped automatically.
   - `NAV` — the bottom-nav / sidebar tabs for the app.
   - `DATA_TYPES` — the per-profile data collections (these define `ALL_KEYS`
     and what syncs).
   - The sample **"items"** page (`renderItems`, the item modal, `saveItem` …) is
     a complete CRUD example. **Duplicate and rename it** for each real entity of
     the new app (e.g. meals, workouts, tasks, clients). Wire each into `NAV`,
     `DATA_TYPES`, `render()`, and `fabAction()`.
   - Replace `renderDashboard` with a real home screen for the domain.

4. **Branding**: edit the gradient/colors in `make-icons.js` and run
   `node make-icons.js` to regenerate `icon-192.png`, `icon-512.png` (and the iOS
   icon if `native/` exists). Update `manifest.json` name/short_name/colors and
   the `<title>` + `theme-color` in `index.html`.

5. **Firebase (cloud sync)** — if the user wants sync:
   - Create a Firebase project, enable **Realtime Database**.
   - Paste the web config into the `firebaseConfig` object in `index.html`.
   - Until configured it runs **local-only** (works fully, just no sync). The
     Settings page shows the live cloud status.
   - Each app MUST use its own Firebase project (or at least its own DB) so data
     never mixes between apps.

6. **Verify before declaring done**: serve the folder
   (`python3 -m http.server`) and drive it with Playwright (login → lobby →
   add/edit/delete an item → reload to confirm persistence → dark mode). There is
   a ready Chromium under Playwright in this environment. Screenshot the key
   screens. Syntax-check the inline script with `node --check`.

7. **Deploy**: it is static. Push to a repo with GitHub Pages or Cloudflare Pages.
   `start_url`/`scope` in `manifest.json` are relative (`./`) so it works under
   any sub-path. To ship an update later: change code, bump `version.txt`.

## Notes & gotchas

- Keep it a single `index.html`. Don't introduce a framework/build step unless
  the user explicitly asks — the no-build simplicity is the whole point.
- The sync engine stores each key under `app_data/<key>` with a timestamp under
  `app_meta/<key>`. Don't rename these nodes per-app unless two apps must share
  one Firebase project — then give each a unique node prefix.
- `_headers` (Cloudflare Pages) forces no-cache on the HTML + `version.txt`.
- `reference/ARCHITECTURE.md` has a deeper explanation of each subsystem — read
  it if you need to change the sync engine or PWA behavior.
