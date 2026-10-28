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
- Sign-off without a server: staff send the month as one sealed file, the Block Integrator, Accountant and
  District Integrator each open it, check it and sign (see "How sign-off works" below)
- Role-aware tabs (Review tab for the Block Integrator, Accountant and District Integrator)

Not in this version yet: GPS stamp (geolocator was removed to get the build working), photo stamp text.

## How sign-off works (no server)

Everything is passed as one file, `*.vlbreport`, over WhatsApp, email or Drive. There is no account and no server.

1. **Staff** open Report, choose the month and tap *Send report for sign-off*. The app packs every trip of the month
   and every odometer photo into one file, seals it and opens the share sheet. The month is then closed for new
   trips unless the report is sent back.
2. **Block Integrator** saves the file, opens Review, taps *Open a report file*. The app runs the checks (below),
   shows the statement, trips and photos, and the BI signs (*Checked, send to Accountant*) or sends it back with a note.
   The BI then shares the file on.
3. **Accountant** does the same (*Verified, send to District Integrator*).
4. **District Integrator** approves, and can also approve the km above the 500 km limit. Payable is
   (km within the limit + approved extra km) x rate.
5. Each person sends the signed file back to the staff member, who opens it (Report, *Open a signed file*) to see
   the sign-offs. If it was sent back, the staff member reads the note, can add notes to locked trips, and sends
   version 2 of the same report.

Every time a file is opened the app checks that: the report fingerprint still matches; each trip still matches its
seal; the trips are linked in order; every odometer photo is present and unchanged (SHA-256); the km and amount
match the trips; and the sign-offs are in order (staff, BI, Accountant, DI), by the right roles, each sealed onto the
one before it. A file that fails is not kept. Two different signatures for the same step are shown as a conflict.

Limits to know about:

- It shows that nothing was changed after it was sealed. It does not prove who a person is: anyone can install
  the app and choose a reviewer role. The sealed meter photos and the WhatsApp trail are what back the names.
- There are no notifications. Staff see progress only when a signed file comes back, so use one WhatsApp group
  with the staff, BI, Accountant and DI.
- Cutting the first or last trips off a month cannot be seen from the file alone. The app warns when a report does
  not continue from the previous month's report held on the phone.

Code: `lib/models/report.dart` (file format), `lib/services/report_service.dart` (seal, checks, signing, file packing),
`lib/screens/signoff_panel.dart` (staff side), `lib/screens/review_screen.dart` (reviewer side).

## Design

The logo is a map pin whose hole is a keyhole (the entry locks), with an odometer under it.
The app is built on the same idea: odometer drums for the month's km, ledger rows for figures,
a four-step sign-off (staff, Block Integrator, Accountant, District Integrator).
Type is Barlow Semi Condensed (OFL, in `assets/fonts`). Colours, glass tints, gradients, text styles and the
Lucide icon set (`AppIcons`) are in `lib/ui/theme.dart`, shared widgets in `lib/ui/widgets.dart`.
The logo source and the script that makes the icons are in `brand/`.

Motion and glass live in `lib/ui/motion.dart`: `GlassCard` (frosted card, lifts on hover and squashes on press
when tappable), `GlassBar` (blurred floating bar), `AuroraBackground`, `GlowButton` (main call to action),
`FadeSlideIn` (staggered entrance), `ThemeToggle`, `SpringIconButton`, `PulseDot` and `Float`.
Every looping or decorative animation stops when the phone asks for reduced motion.

The app opens with `lib/screens/splash_screen.dart`: it starts on the same green and logo as the phone's launch
screen, then the pin hops, the keyhole turns and locks, the odometer drums roll round and the name rises in.
Tap to skip.

## Screens test

`test/report_flow_test.dart` covers the report file and sign-off logic: sealing, signing rules, tampering cases (edited
trip, swapped photo, removed sign-off and more) and a phone-to-phone round with file passing.

`test/shots_test.dart` opens every screen at phone size, in light, dark and large-text settings, and fails on any
layout overflow. It is skipped unless `SHOTS=1`. CI runs it on every push and attaches the PNGs to the run as the
`screens` artifact.

```bash
flutter test                                  # logic tests
SHOTS=1 flutter test test/shots_test.dart     # screens, PNGs go to shots/
```

## Build APK

This repo includes a GitHub Actions workflow that analyzes, tests and builds a release APK on every push to main
(and to `feature/**` branches).

1. Push, or go to the Actions tab and run the workflow manually.
2. Open the run and download `vehicle-log-book-apk` from the Artifacts list.

Local build:
```bash
flutter pub get
flutter build apk --release
```
