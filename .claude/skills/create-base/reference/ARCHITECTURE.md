# Base architecture — how each tool works

Everything is one `index.html` (HTML + CSS + JS inline). No build step.
This document explains the subsystems so you can extend or change them safely.

## File map

| File | Purpose |
|------|---------|
| `index.html` | The entire app (UI + logic). |
| `manifest.json` | PWA metadata (name, icons, colors). `start_url`/`scope` are `./` so it works on any sub-path. |
| `sw.js` | Service worker: network-first for HTML, cache-first for assets, offline fallback. |
| `version.txt` | Single integer. Bump it to force every client to reload fresh code. |
| `_headers` | Cloudflare Pages no-cache rules for the HTML + version.txt. |
| `make-icons.js` | Pure-Node PNG generator → `icon-192/512.png` (+ iOS 1024 icon). |
| `native/` | Optional Capacitor iOS wrapper. |

## Data model & storage

- Each profile's data lives under keys `"<profile>_<type>"` (e.g. `me_items`).
  `ALL_KEYS` is the cartesian product of `PROFILES` × `DATA_TYPES`.
- `load(key)` reads `localStorage['s_'+key]` (defaults to `[]`).
- `save(key, val)` does three things, in order:
  1. write `localStorage` immediately (always succeeds, instant UI),
  2. record the change in the **pending queue** on disk,
  3. try to push to the cloud now.
- Each value is a JSON array of records `{ id, ... }`. `genId()` makes ids.

## Sync engine (the important part)

Goal: **never lose a write**, even offline or if the app is killed mid-save.

- `_pending` is a map `key → {data, ts}` persisted at `localStorage['_sync_pending']`.
- `save()` adds to `_pending` and calls `_pushKey()`.
- `_pushKey()` writes `app_data/<key>` and `app_meta/<key>` (a timestamp) to
  Firebase in one atomic `update()`. On success it waits **8 seconds** before
  clearing the pending entry — this guards against Firebase replication lag
  overwriting a fresh local write with a slightly stale cloud read.
- On failure the entry stays queued; a timer retries every 20s, and `flushPending()`
  runs on focus.
- **Startup merge** (`initFirebase`): for each key, if there's a pending local
  change it wins; otherwise compare `app_meta` timestamp vs the local timestamp
  and take the newer. First load (no local ts) takes the cloud.
- **Live merge** (`_syncFromCloud`): on tab focus, every 3 min, it pulls cloud
  values that are strictly newer than local and that have no pending local edit.

If `firebaseConfig.apiKey` is still the placeholder, `CLOUD_CONFIGURED` is false
and the app runs **local-only** — fully functional, just no cross-device sync.

## Auto-backup

`autoBackup()` (3s after load) writes a full snapshot to `app_backups/<date>` in
Firebase plus a local copy. `_pruneBackups()` keeps the last 30 daily snapshots
and one monthly checkpoint forever. `restoreFromAutoBackup()` lists them and
restores a chosen one. `exportBackup()` / `importBackup()` do the same via a JSON file.

## Auth → Lobby → App

- `doLogin()` checks `PASS`, stores `app_authed`, then `afterAuth()`.
- `afterAuth()`: if there's a single profile it enters it directly; otherwise
  shows the **lobby**.
- `enterPerson(id)` sets `currentPerson`, applies that profile's accent (CSS vars),
  and shows the app shell.

## Navigation & rendering

- `NAV` drives both the desktop sidebar and the mobile bottom nav (`buildNav()`).
- `showPage(name)` toggles `.active` on `#page-<name>` and the nav links, then
  calls `render(name)` which dispatches to the matching `renderX()` function.
- `refreshAll()` re-renders the current page (called after every data change and
  after a cloud sync).
- Each page is rendered by setting `innerHTML` — simple, fast, no framework.
- The **FAB** (`fabAction()`) opens the primary "add" modal for the current page.

## Adding a new entity (the common task)

1. Add its name to `DATA_TYPES`.
2. Add a tab to `NAV` and a `<div id="page-X" class="page"></div>` in `.main`.
3. Copy the `renderItems` function → `renderX`, and register it in `render()`.
4. Copy the item modal (`<div class="modal" id="modal-X">`) and its
   `openXModal` / `saveX` / `deleteX` functions.
5. Route the FAB: `function fabAction(){ if(currentPage==='X') openXModal(); else ... }`.

## Theming

CSS variables on `:root` (light) and `[data-theme="dark"]`. `toggleTheme()`
flips `data-theme` on `<html>` and persists it. Each profile overrides `--accent`
at runtime. Add components by reusing the existing tokens.

## Deploy & update

Static hosting (GitHub Pages / Cloudflare Pages). To ship an update: edit code,
**bump `version.txt`**. The service worker is network-first for HTML and the
`checkVersion()` routine forces a fresh reload (with a `?_v=` cache-buster, which
iOS standalone PWAs need).

## Verifying changes

```bash
python3 -m http.server 8099       # serve the folder
node --check <(extract inline script)   # syntax check
# drive with Playwright (Chromium is preinstalled in this environment):
#   login → lobby → add/edit/delete → reload (persistence) → dark mode → screenshots
```
External CDN errors (Firebase/fonts) in a sandbox are network-only, not app bugs.
