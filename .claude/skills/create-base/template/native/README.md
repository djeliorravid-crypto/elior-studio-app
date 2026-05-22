# Native iOS wrapper (Capacitor)

Turns the same `index.html` web app into a real iOS app (with local
notifications that work when the app is closed).

## One-time setup (on a Mac)

1. Install **Xcode** (App Store) and have a free **Apple ID**.
2. Edit `capacitor.config.json`: set a unique `appId` (e.g. `com.you.appname`)
   and the `appName`.
3. From this `native/` folder:
   ```bash
   npm install
   npm run sync          # copies the web app into www/ and into the iOS project
   npx cap add ios       # first time only — generates the ios/ project
   npx cap open ios      # opens Xcode
   ```

## In Xcode

1. **Signing & Capabilities** → Add your Apple ID → pick your Personal Team.
2. Confirm the **Bundle Identifier** matches your `appId`.
3. Connect your iPhone, select it, press ▶ Run.
4. On the iPhone: **Settings → General → VPN & Device Management** → trust your key.

## Update after web changes

```bash
npm run sync   # then ▶ Run again in Xcode
```

Free Apple ID builds expire every 7 days — re-run to refresh. An Apple Developer
account ($99/yr) is only needed for the App Store / 1-year installs.

## App icon

Run `node ../make-icons.js` after editing the gradient in `make-icons.js` — it
writes the iOS 1024px icon into `ios/.../AppIcon.appiconset/` automatically once
the ios project exists.
