# Palay Patrol mobile app on Vercel (Flutter web)

This folder builds both the Android APK and a Flutter **web** version of the
app that runs in a phone browser (Chrome on Android, Safari on iOS).

## Deploy the web app

1. Deploy the API first (`rice-pest-api`) and note its HTTPS address,
   e.g. `https://rice-pest-api.vercel.app`.
2. Create a new Vercel project from this repository with
   **Root Directory = `mobile-app`**. `vercel.json` already sets
   `framework: null`, the install/build commands and `outputDirectory: build/web`.
3. In *Settings → Environment Variables* add **`API_URL`** = the API address
   (must start with `https://`). It is compiled into the app, so redeploy
   after changing it. The build stops with a clear error if it is missing.
4. On the API project, add the web app's address (e.g.
   `https://palay-patrol.vercel.app`) to `CORS_ALLOWED_ORIGINS`
   (or allow preview URLs with `CORS_ALLOWED_ORIGIN_REGEX`), otherwise the
   browser blocks every request.

What the build does (`vercel-build.sh`):

- `install`: shallow-clones Flutter `3.47.1` (override with `FLUTTER_VERSION`),
  `flutter config --enable-web`, `flutter pub get`.
- `build`: `flutter build web --release --dart-define=API_URL=$API_URL`.

`web/sqlite3.wasm` and `web/sqflite_sw.js` (SQLite for the browser) are
committed, so no setup step runs on Vercel. If you upgrade
`sqflite_common_ffi_web`, run `dart run sqflite_common_ffi_web:setup` locally
and commit the two regenerated files.

### Deploying a prebuilt `build/web` instead

Building Flutter on Vercel takes a few minutes. To skip it, build locally:

```
flutter build web --release --dart-define=API_URL=https://<api>.vercel.app
```

commit `build/web` (make sure `.gitignore` does not exclude it), then in the
Vercel project settings override **Install Command** with `echo skip` and
**Build Command** with `echo prebuilt` (keep Output Directory `build/web`).

## Build the APK against the deployed API

```
flutter build apk --release --dart-define=API_URL=https://<api>.vercel.app
```

With `API_URL` set, the app skips Wi-Fi/LAN discovery and talks only to that
HTTPS address. Without it, the APK keeps the old behaviour (finds a local
server on the same network).

Local web development against a local API: `flutter run -d chrome` (no
`API_URL`) uses `http://localhost:8000`.

## How the web version differs (limitations)

- **Offline storage is per browser and per site.** Outbox, cached records and
  photos are kept in the browser (SQLite in WebAssembly + IndexedDB). They do
  not move to another browser or phone, and clearing site data, private
  browsing, or iOS Safari's storage eviction (sites not opened for ~7 days,
  unless added to the Home Screen) deletes observations not yet sent.
- **No phone notifications.** `flutter_local_notifications` is not used on the
  web; the in-app notifications list and badge still work.
- **Camera needs HTTPS and permission.** The browser asks for camera access
  when the camera screen opens. If it was blocked, re-allow it in the
  browser's site settings, then tap retry. Flash/torch modes are usually not
  supported by mobile browsers; "Insert image" (gallery) works everywhere.
- **Location**: the browser asks for location permission; the app cannot open
  system settings or watch whether location is turned on/off, so tap the
  location button again after enabling it.
- **iOS Safari quirks**: camera only works in Safari (or a Home Screen app) on
  iOS 14.3+; the camera may need a tap to start after switching apps; storage
  limits are smaller than on Android.
- **Sync only while the tab is open.** There is no background service; queued
  observations upload when the page is open and the server is reachable.
- **No LAN discovery.** A browser cannot scan the network; the web build
  always uses `API_URL`.
