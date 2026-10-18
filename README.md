# Vehicle Log Book (Flutter)

Flutter port of the single-file HTML Vehicle Log Book app (DSC-VLB schema).

## Features implemented

- Setup / profile (name, staff code, role, vehicle)
- Today screen: the month's km on odometer drums, a limit bar, the open trip and recent trips, with Start / End / Log-finished trip
- Trip form: start, end or log a finished trip, with an odometer photo for every reading,
  forward-only meter checks, late-entry reason, meter-reset reason and prior approval above the monthly limit
- Every saved trip is locked with a SHA-256 seal, chained to the previous trip (same layout as the HTML app)
- Cancel an open trip (stays in the log as cancelled, 0 km)
- Local storage (SharedPreferences + files for photos)
- Log Book by month, grouped by day, with a detail sheet per trip: odometer photos, flags, notes and a seal check
- Monthly report as a statement: km within and above the limit, amount payable, km by project, trips worth a second look
- Settings: office rules, light / dark / phone theme, integrity check of all locked entries, full data erase
- Role-aware tabs (Review placeholder for BI / Accountant / DI)

Not in this version yet: GPS stamp (geolocator was removed to get the build working), photo stamp text,
monthly report file, and the Block Integrator / Accountant / District Integrator review screens.

## Design

The logo is a map pin whose hole is a keyhole (the entry locks), with an odometer under it.
The app is built on the same idea: odometer drums for the month's km, ledger rows for figures,
a four-step sign-off (staff, Block Integrator, Accountant, District Integrator).
Type is Barlow Semi Condensed (OFL, in `assets/fonts`). Colours and text styles are in `lib/ui/theme.dart`,
shared widgets in `lib/ui/widgets.dart`. The logo source and the script that makes the icons are in `brand/`.

## Screens test

`test/shots_test.dart` opens every screen at phone size, in light, dark and large-text settings, and fails on any
layout overflow. It is skipped unless `SHOTS=1`. CI runs it on every push and attaches the PNGs to the run as the
`screens` artifact.

```bash
SHOTS=1 flutter test test/shots_test.dart   # PNGs go to shots/
```

## Build APK

This repo includes a GitHub Actions workflow that builds a release APK on every push to main.

1. Push to main or go to Actions tab and run the workflow manually.
2. Download the APK from the workflow artifacts.

Local build:
```bash
flutter pub get
flutter build apk --release
```
