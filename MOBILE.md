# Ravid Studio — iOS / Capacitor

Production setup for shipping the existing web app to Elior's iPhone
via TestFlight, without rewriting anything.

## Architecture

- Web app continues to live at /index.html, /contract.html, /workshop.html,
  /proposal.html — same code that powers the GitHub Pages PWA.
- Capacitor wraps the web app in a native iOS shell.
- The shell loads the local web assets (offline-first), with Firebase /
  EmailJS reaching out over the network exactly as they do today.

## What's in this branch (`mobile`)

- `package.json` — npm manifest with the three Capacitor packages
  (`@capacitor/core`, `@capacitor/cli`, `@capacitor/ios`).
- `capacitor.config.json` — app identity (bundle id, name, splash
  background) and iOS-specific settings.
- `.github/workflows/ios-testflight.yml` — CI that builds the iOS
  archive on every push to `mobile` / `main` and uploads to TestFlight.
- `ios/` (created by `npx cap add ios` on first CI run) — the
  native Xcode project. Not committed initially so the first CI run
  generates it cleanly.

## One-time setup (Elior, ~15 minutes)

After Apple approves the Developer Program enrollment:

1. **In App Store Connect**, create an app:
   - Bundle ID: `com.ravidstudio.app`
   - Name: `Ravid Studio`
   - SKU: `ravid-studio-001`

2. **Generate an App Store Connect API key** (Users & Access → Keys):
   - Role: `App Manager`
   - Download the `.p8` file (one-time download!)
   - Note the `Key ID` and `Issuer ID`

3. **Create signing cert + provisioning profile** (Certificates, IDs &
   Profiles → Profiles):
   - Distribution certificate (one-time, valid 1 year)
   - App Store provisioning profile for `com.ravidstudio.app`
   - Export the certificate as `.p12` with a password

4. **Add GitHub Secrets** to the repo (Settings → Secrets and variables
   → Actions):

   | Secret name                              | What it is                                                           |
   |------------------------------------------|----------------------------------------------------------------------|
   | `APP_STORE_CONNECT_API_KEY_ID`           | 10-char Key ID from App Store Connect                                |
   | `APP_STORE_CONNECT_API_ISSUER_ID`        | UUID Issuer ID from App Store Connect                                |
   | `APP_STORE_CONNECT_API_PRIVATE_KEY`      | Contents of the `.p8` file (full PEM, with BEGIN/END lines)          |
   | `IOS_DISTRIBUTION_CERTIFICATE_BASE64`    | `base64 -i Certificate.p12 -o cert.b64`, then paste the b64 contents |
   | `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`  | Password used when exporting the .p12                                |
   | `IOS_PROVISIONING_PROFILE_BASE64`        | Base64 of the .mobileprovision file                                  |

5. **In TestFlight**: add Elior's Apple ID as an internal tester.
   Add anyone else later as needed.

## Day-to-day workflow

Every push to `mobile` (or merge to `main`) automatically:

1. Runs the GitHub Actions workflow on a macOS runner.
2. Sets up Node, installs Capacitor, syncs the web assets into iOS.
3. Builds the iOS archive and exports a signed IPA.
4. Uploads the IPA to App Store Connect.
5. TestFlight processes it (~15 min) and pushes a notification to
   every internal tester's device that a new build is available.

End-to-end from commit to phone: ~25-30 minutes, fully automated.

## Local development (only needed if iterating native code)

Requires a Mac with Xcode installed:

```sh
npm install
npx cap add ios          # only the first time
npx cap sync ios         # after every web-side change
npx cap open ios         # opens Xcode
```

For most pushes Elior never touches Xcode — CI does everything.
