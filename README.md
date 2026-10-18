# Vehicle Log Book (Flutter)

Flutter port of the single-file HTML Vehicle Log Book app (DSC-VLB schema).

## Features implemented

- Setup / profile (name, staff code, role, vehicle)
- Today screen with monthly km gauge and Start / End / Log-finished trip
- Trip form with camera photo capture and optional GPS
- Local storage (SharedPreferences + files for photos)
- Log Book list by month
- Report summary
- Settings and full data erase
- Role-aware tabs (Review placeholder for BI / Accountant / DI)

## Build APK

This repo includes a GitHub Actions workflow that builds a release APK on every push to main.

1. Push to main or go to Actions tab and run the workflow manually.
2. Download the APK from the workflow artifacts.

Local build:
```bash
flutter pub get
flutter build apk --release
```
