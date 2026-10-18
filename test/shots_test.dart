// Renders every screen at phone size and writes PNGs to shots/.
// It also fails on any layout overflow or exception while building a screen.
//
// Run:  SHOTS=1 flutter test test/shots_test.dart
// Without SHOTS=1 the tests are skipped, so a plain `flutter test` stays quick.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vehicle_log_book/main.dart';
import 'package:vehicle_log_book/models/profile.dart';
import 'package:vehicle_log_book/models/trip.dart';
import 'package:vehicle_log_book/services/app_state.dart';
import 'package:vehicle_log_book/services/trip_rules.dart';
import 'package:vehicle_log_book/ui/format.dart';
import 'package:vehicle_log_book/ui/trip_tiles.dart';

const Size _phone = Size(360, 780);
const Size _tall = Size(360, 1500);
const Size _xtall = Size(360, 2300);

final GlobalKey _shotKey = GlobalKey();
final String _out = Platform.environment['SHOTS_DIR'] ?? 'shots';
final bool _enabled = Platform.environment['SHOTS'] == '1';

// ---------------------------------------------------------------- fonts

Future<void> _loadFonts() async {
  final barlow = FontLoader('BarlowSC');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/BarlowSemiCondensed-$w.ttf').readAsBytesSync();
    barlow.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  }
  await barlow.load();

  // Material icons, so icons draw as icons and not as boxes.
  final icons = Platform.environment['MATERIAL_ICONS'];
  if (icons != null && icons.isNotEmpty && File(icons).existsSync()) {
    final l = FontLoader('MaterialIcons');
    l.addFont(Future<ByteData>.value(ByteData.sublistView(File(icons).readAsBytesSync())));
    await l.load();
  }

  // Barlow has no rupee sign. On a phone the system font supplies it; here a stand-in does.
  final sans = Platform.environment['FALLBACK_FONT'];
  if (sans != null && sans.isNotEmpty && File(sans).existsSync()) {
    final l = FontLoader('Roboto');
    l.addFont(Future<ByteData>.value(ByteData.sublistView(File(sans).readAsBytesSync())));
    await l.load();
  }
}

// ---------------------------------------------------------------- data

String _day(int back) {
  final now = DateTime.now();
  final b = back > now.day - 1 ? now.day - 1 : back;
  return dateStr(DateTime(now.year, now.month, now.day - b));
}

class _Spec {
  final int back;
  final String project;
  final String to;
  final String activity;
  final String task;
  final int km;
  final bool late;
  final bool reset;
  final Map<String, dynamic>? prior;
  const _Spec(this.back, this.project, this.to, this.activity, this.task, this.km,
      {this.late = false, this.reset = false, this.prior});
}

const _vehicle = 'MH39 AB 1234';

Future<AppState> _seed({required bool profile, required String scenario}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final dir = Directory.systemTemp.createTempSync('vlb_photos');
  final s = AppState();
  await s.init(photosDir: dir);
  if (!profile) return s;

  await s.setProfile(Profile(
    id: 'DSC-NDB-014',
    name: 'Jitendra Sonawane',
    designation: 'District Programme Integrator',
    block: 'Nandurbar',
    district: 'Nandurbar',
    mobile: '9890000000',
    role: 'staff',
    vehicles: [Vehicle(no: _vehicle, type: 'Two-wheeler')],
    created: nowIso(),
  ));

  final specs = <_Spec>[
    const _Spec(9, 'ABF (Axis Bank Foundation)', 'Chinchpada', 'Village meeting',
        'PIC meeting on net plan; checked farm pond work', 46),
    const _Spec(8, 'NABARD', 'Akkalkuwa, Moliwada', 'Training / workshop', 'Farmer training on soil health card', 66),
    const _Spec(6, 'VCS 4285 Carbon', 'Dhadgaon', 'Survey / planning', 'Baseline survey of cookstove households', 59,
        late: true),
    const _Spec(5, 'Project SAHAS', 'Shahada', 'Work supervision', 'Checked check dam work and recorded measurements', 25,
        reset: true),
    const _Spec(3, 'ABF (Axis Bank Foundation)', 'Taloda, Bhagdari, Kalambu', 'Monitoring visit',
        'Monitoring of SHG savings and loan registers in three villages', 143),
    const _Spec(1, 'Lokkalyan CSR', 'Navapur', 'Govt. office / bank', 'Submitted utilisation certificate at the block office', 54),
    if (scenario == 'over') ...[
      _Spec(1, 'NABARD', 'Dhule, Sakri', 'Monitoring visit', 'Review of watershed works with the cluster team', 118, prior: {
        'by': 'Mr. Patil (District Integrator)',
        'date': _day(2),
        'mode': 'WhatsApp',
        'ref': 'Message of 15-10, 10:05',
        'none': false,
      }),
      _Spec(0, 'ABF (Axis Bank Foundation)', 'Pimpalner', 'Monitoring visit', 'Follow-up visit to SHG federation office', 74,
          prior: {'by': '', 'date': '', 'mode': '', 'ref': '', 'none': true}),
    ],
  ];

  var odo = 18240;
  var n = 0;
  for (final sp in specs) {
    n += 1;
    final d = _day(sp.back);
    final o = odo;
    final c = odo + sp.km;
    odo = c;
    final k1 = 'p${n}a';
    final k2 = 'p${n}b';
    final b1 = File('test/fixtures/odo${(n % 4) + 1}.jpg').readAsBytesSync();
    final b2 = File('test/fixtures/odo${((n + 1) % 4) + 1}.jpg').readAsBytesSync();
    await s.storage.savePhoto(k1, b1);
    await s.storage.savePhoto(k2, b2);
    await s.createTrip(Trip(
      id: 't$n',
      mode: 'full',
      date: d,
      month: monthOf(d),
      project: sp.project,
      vehicle: _vehicle,
      vtype: 'Two-wheeler',
      from: 'Nandurbar',
      to: sp.to,
      activity: sp.activity,
      task: sp.task,
      start: Reading(km: o, photoKey: k1, photoHash: sha256.convert(b1).toString(), at: isoAt(d, '09:40')),
      end: Reading(
        km: c,
        photoKey: k2,
        photoHash: sha256.convert(b2).toString(),
        at: isoAt(d, '17:05'),
        returnTo: 'Nandurbar',
        remarks: n == 1 ? 'Hall rent paid in cash' : null,
      ),
      km: sp.km,
      status: 'closed',
      late: sp.late ? {'reason': 'No network in the village, entered next morning'} : null,
      meterReset: sp.reset ? {'reason': 'Speedometer replaced at garage'} : null,
      prior: sp.prior,
      notes: n == 1 ? [Note(at: nowIso(), text: 'Receipt for the hall rent is with the accountant.')] : <Note>[],
      loggedAt: isoAt(d, '17:10'),
    ));
  }

  // One trip that was cancelled.
  final ck = 'pc';
  final cb = File('test/fixtures/odo1.jpg').readAsBytesSync();
  await s.storage.savePhoto(ck, cb);
  final cancelled = Trip(
    id: 'tc',
    mode: 'start',
    date: _day(2),
    month: monthOf(_day(2)),
    project: 'Project SAHAS',
    vehicle: _vehicle,
    vtype: 'Two-wheeler',
    from: 'Nandurbar',
    to: 'Khapar',
    activity: 'Village meeting',
    task: 'Gram sabha meeting',
    start: Reading(km: odo, photoKey: ck, photoHash: sha256.convert(cb).toString(), at: isoAt(_day(2), '08:50')),
    status: 'open',
    loggedAt: isoAt(_day(2), '08:51'),
  );
  await s.createTrip(cancelled);
  await s.cancelTrip(cancelled, 'Meeting postponed by the sarpanch');

  if (scenario == 'open') {
    final b = File('test/fixtures/odo2.jpg').readAsBytesSync();
    await s.storage.savePhoto('po', b);
    final started = DateTime.now().subtract(const Duration(hours: 2, minutes: 10));
    await s.createTrip(Trip(
      id: 'to',
      mode: 'start',
      date: todayStr(),
      month: currentMonth(),
      project: 'ABF (Axis Bank Foundation)',
      vehicle: _vehicle,
      vtype: 'Two-wheeler',
      from: 'Nandurbar',
      to: 'Chinchpada, Visarwadi',
      activity: 'Village meeting',
      task: 'Review meeting with the SHG federation',
      start: Reading(
        km: odo,
        photoKey: 'po',
        photoHash: sha256.convert(b).toString(),
        at: started.toUtc().toIso8601String(),
      ),
      status: 'open',
      loggedAt: started.toUtc().toIso8601String(),
    ));
  }
  return s;
}

// ---------------------------------------------------------------- harness

Future<AppState> _state(WidgetTester tester, {bool profile = true, String scenario = 'open'}) async {
  final s = await tester.runAsync(() => _seed(profile: profile, scenario: scenario));
  return s!;
}

Future<void> _pumpApp(
  WidgetTester tester,
  AppState state, {
  ThemeMode mode = ThemeMode.light,
  Size size = _phone,
  double textScale = 1.0,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 28, bottom: 16);
  tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 16);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _shotKey,
      child: ChangeNotifierProvider<AppState>.value(
        value: state,
        child: VehicleLogApp(themeMode: mode),
      ),
    ),
  );

  // Images load with real I/O, which the test clock does not wait for. Load them first.
  final ctx = tester.element(find.byType(MaterialApp));
  await tester.runAsync(() async {
    await precacheImage(const AssetImage('assets/logo/logo_mark.png'), ctx);
    for (final t in state.trips) {
      for (final r in <Reading?>[t.start, t.end]) {
        final k = r?.photoKey;
        if (k != null) await precacheImage(FileImage(File(state.storage.photoPath(k))), ctx);
      }
    }
  });
  await tester.pumpAndSettle();
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$_out/$name.png');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text).first;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, int index, String text) async {
  final f = find.byType(TextField);
  if (f.evaluate().length > index) {
    await tester.enterText(f.at(index), text);
    await tester.pump();
  }
}

// ---------------------------------------------------------------- tests

void main() {
  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  testWidgets('setup', (tester) async {
    final s = await _state(tester, profile: false);
    await _pumpApp(tester, s, size: _tall);
    await _shot(tester, '01_setup');
  }, skip: !_enabled);

  testWidgets('today with a trip open', (tester) async {
    final s = await _state(tester, scenario: 'open');
    await _pumpApp(tester, s);
    await _shot(tester, '02_today_open');
    await _resize(tester, _tall);
    await _shot(tester, '02_today_open_tall');
  }, skip: !_enabled);

  testWidgets('today over the limit', (tester) async {
    final s = await _state(tester, scenario: 'over');
    await _pumpApp(tester, s);
    await _shot(tester, '03_today_over');
  }, skip: !_enabled);

  testWidgets('log book and detail', (tester) async {
    final s = await _state(tester, scenario: 'over');
    await _pumpApp(tester, s, size: _tall);
    await _tab(tester, 'Log book');
    await _shot(tester, '04_log');
    await tester.tap(find.byType(TripTile).at(3));
    await tester.pumpAndSettle();
    await _shot(tester, '05_detail_closed');
    await _back(tester);
    await tester.tap(find.byType(TripTile).at(0));
    await tester.pumpAndSettle();
    await _shot(tester, '06_detail_flagged');
  }, skip: !_enabled);

  testWidgets('open trip detail', (tester) async {
    final s = await _state(tester, scenario: 'open');
    await _pumpApp(tester, s, size: _tall);
    await tester.tap(find.byType(TripTile).first);
    await tester.pumpAndSettle();
    await _shot(tester, '07_detail_open');
  }, skip: !_enabled);

  testWidgets('report and settings', (tester) async {
    final s = await _state(tester, scenario: 'over');
    await _pumpApp(tester, s, size: _tall);
    await _tab(tester, 'Report');
    await _shot(tester, '08_report');
    await _tab(tester, 'Settings');
    await _shot(tester, '09_settings');
  }, skip: !_enabled);

  testWidgets('forms', (tester) async {
    final s = await _state(tester, scenario: 'over');
    await _pumpApp(tester, s, size: _xtall);
    await _tapText(tester, 'Start a trip');
    await _shot(tester, '10_form_start');
    await _back(tester);

    await _tapText(tester, 'Log a finished trip');
    await _type(tester, 1, 'Chinchpada');
    await _type(tester, 2, 'Meeting with the SHG federation');
    await _type(tester, 3, '19000');
    await _type(tester, 4, '19157');
    await _shot(tester, '11_form_full_over_limit');
    await _back(tester);
  }, skip: !_enabled);

  testWidgets('end trip form', (tester) async {
    final s = await _state(tester, scenario: 'open');
    await _pumpApp(tester, s, size: _xtall);
    await _tapText(tester, 'End trip');
    await _shot(tester, '12_form_end');
  }, skip: !_enabled);

  testWidgets('dark', (tester) async {
    final s = await _state(tester, scenario: 'open');
    await _pumpApp(tester, s, mode: ThemeMode.dark);
    await _shot(tester, '13_dark_today');
    await _resize(tester, _tall);
    await tester.tap(find.byType(TripTile).at(1));
    await tester.pumpAndSettle();
    await _shot(tester, '14_dark_detail');
    await _back(tester);
    await _tab(tester, 'Report');
    await _shot(tester, '15_dark_report');
  }, skip: !_enabled);

  testWidgets('large text', (tester) async {
    final s = await _state(tester, scenario: 'open');
    await _pumpApp(tester, s, size: _tall, textScale: 1.4);
    await _shot(tester, '16_large_today');
    await _tab(tester, 'Log book');
    await _shot(tester, '17_large_log');
    await _tab(tester, 'Settings');
    await _shot(tester, '18_large_settings');
  }, skip: !_enabled);

  testWidgets('reviewer role', (tester) async {
    final s = await _state(tester, scenario: 'over');
    await tester.runAsync(() async {
      final p = s.profile!;
      p.role = 'di';
      await s.setProfile(p);
    });
    await _pumpApp(tester, s, size: _phone);
    await _tab(tester, 'Review');
    await _shot(tester, '19_review');
    expect(roleLabel('di'), 'District Integrator');
  }, skip: !_enabled);
}
