# Vehicle Log Book (Flutter)

Flutter port of the single-file HTML Vehicle Log Book app (DSC-VLB schema).

## Features implemented

- Setup / profile (name, staff code, role, vehicle)
- Today screen with monthly km gauge and Start / End / Log-finished trip
- Trip form: start, end or log a finished trip, with an odometer photo for every reading,
  forward-only meter checks, late-entry reason, meter-reset reason and prior approval above the monthly limit
- Every saved trip is locked with a SHA-256 seal, chained to the previous trip (same layout as the HTML app)
- Cancel an open trip (stays in the log as cancelled, 0 km)
- Local storage (SharedPreferences + files for photos)
- Log Book list by month
- Report summary
- Settings and full data erase
- Role-aware tabs (Review placeholder for BI / Accountant / DI)

Not in this version yet: GPS stamp (geolocator was removed to get the build working), photo stamp text,
monthly report file, and the Block Integrator / Accountant / District Integrator review screens.

## Build APK

This repo includes a GitHub Actions workflow that builds a release APK on every push to main.

1. Push to main or go to Actions tab and run the workflow manually.
2. Download the APK from the workflow artifacts.

Local build:
```bash
flutter pub get
flutter build apk --release
```
