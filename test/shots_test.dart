// Renders every screen at phone size and writes PNGs to shots/.
// It also fails on any layout overflow or exception while building a screen.
//
// Run:  SHOTS=1 flutter test test/shots_test.dart
// Without SHOTS=1 the tests are skipped, so a plain `flutter test` stays quick.
import 'dart:convert';
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
import 'package:vehicle_log_book/models/report.dart';
import 'package:vehicle_log_book/models/trip.dart';
import 'package:vehicle_log_book/services/app_state.dart';
import 'package:vehicle_log_book/services/report_service.dart';
import 'package:vehicle_log_book/services/trip_rules.dart';
import 'package:vehicle_log_book/ui/format.dart';
import 'package:vehicle_log_book/ui/signoff_widgets.dart';
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

  // Lucide icons, from the package in the pub cache.
  final lucide = _packageFile('lucide_icons_flutter', 'assets/lucide.ttf');
  if (lucide != null) {
    final l = FontLoader('packages/lucide_icons_flutter/Lucide');
    l.addFont(Future<ByteData>.value(ByteData.sublistView(lucide.readAsBytesSync())));
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

/// A file inside a dependency, found through the package config `pub get` writes.
File? _packageFile(String package, String path) {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) return null;
  final packages = (jsonDecode(config.readAsStringSync()) as Map<String, dynamic>)['packages'] as List<dynamic>;
  for (final p in packages.cast<Map<String, dynamic>>()) {
    if (p['name'] != package) continue;
    var root = Uri.parse(p['rootUri'] as String);
    if (!root.path.endsWith('/')) root = root.replace(path: '${root.path}/');
    final dir = root.isAbsolute ? root : config.parent.uri.resolveUri(root);
    final f = File.fromUri(dir.resolve(path));
    return f.existsSync() ? f : null;
  }
  return null;
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
    const _Spec(
        5, 'Project SAHAS', 'Shahada', 'Work supervision', 'Checked check dam work and recorded measurements', 25,
        reset: true),
    const _Spec(3, 'ABF (Axis Bank Foundation)', 'Taloda, Bhagdari, Kalambu', 'Monitoring visit',
        'Monitoring of SHG savings and loan registers in three villages', 143),
    const _Spec(1, 'Lokkalyan CSR', 'Navapur', 'Govt. office / bank',
        'Submitted utilisation certificate at the block office', 54),
    if (scenario == 'over') ...[
      _Spec(1, 'NABARD', 'Dhule, Sakri', 'Monitoring visit', 'Review of watershed works with the cluster team', 118,
          prior: {
            'by': 'Mr. Patil (District Integrator)',
            'date': _day(2),
            'mode': 'WhatsApp',
            'ref': 'Message of 15-10, 10:05',
            'none': false,
          }),
      _Spec(0, 'ABF (Axis Bank Foundation)', 'Pimpalner', 'Monitoring visit',
          'Follow-up visit to SHG federation office', 74,
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


// ---------------------------------------------------------------- report fixtures

final Profile _biPerson = Profile(
  id: 'DSC-NDB-021',
  name: 'Ramesh Patil',
  designation: 'Block Integrator',
  block: 'Nandurbar',
  district: 'Nandurbar',
  mobile: '9890000001',
  role: 'bi',
  created: '2026-01-01T00:00:00Z',
);
final Profile _accPerson = Profile(
  id: 'DSC-NDB-002',
  name: 'Meena Shah',
  designation: 'Accountant',
  block: 'Nandurbar',
  district: 'Nandurbar',
  mobile: '9890000002',
  role: 'acc',
  created: '2026-01-01T00:00:00Z',
);
final Profile _diPerson = Profile(
  id: 'DSC-NDB-001',
  name: 'Anil Deshmukh',
  designation: 'District Integrator',
  block: 'Nandurbar',
  district: 'Nandurbar',
  mobile: '9890000003',
  role: 'di',
  created: '2026-01-01T00:00:00Z',
);
final Profile _otherStaff = Profile(
  id: 'DSC-NDB-030',
  name: 'Kavita Gavit',
  designation: 'Field Coordinator',
  block: 'Akkalkuwa',
  district: 'Nandurbar',
  mobile: '9890000030',
  role: 'staff',
  created: '2026-01-01T00:00:00Z',
);

/// Applies sign-offs in order: 'bi', 'bi-return', 'acc', 'di'.
ReportPackage _signSteps(ReportPackage p, List<String> steps) {
  var r = p;
  for (final st in steps) {
    switch (st) {
      case 'bi':
        r = signReport(r, _biPerson, decision: 'forward', remarks: 'Trips match the field diary. Meter photos are clear.');
        break;
      case 'bi-return':
        r = signReport(r, _biPerson,
            decision: 'return', remarks: 'The task for the Dhadgaon trip is too short. Add the details and send again.');
        break;
      case 'acc':
        r = signReport(r, _accPerson, decision: 'forward', remarks: 'Km and rate checked against the vouchers.');
        break;
      case 'di':
        r = signReport(r, _diPerson, decision: 'approve', excessApproved: true, remarks: 'Approved with the extra km.');
        break;
    }
  }
  return r;
}

/// A staff phone whose month was sent for sign-off, then signed by [steps].
Future<AppState> _staffWithReport(WidgetTester tester, List<String> steps) async {
  final s = await tester.runAsync(() async {
    final a = await _seed(profile: true, scenario: 'over');
    final sent = await a.submitReport(currentMonth());
    final p = _signSteps(sent, steps);
    await a.storage.saveReport(p);
    a.reports = [p];
    return a;
  });
  return s!;
}

/// A reviewer phone holding reports from different staff, each signed by the given steps.
Future<AppState> _reviewerWithReports(WidgetTester tester, Profile me, List<List<String>> reports) async {
  final s = await tester.runAsync(() async {
    final staff = await _seed(profile: true, scenario: 'over');
    final month = currentMonth();
    final trips = staff.tripsOfMonth(month);
    final photos = <String, List<int>>{};
    for (final t in trips) {
      for (final k in photoKeysOf(t)) {
        photos[k] = (await staff.storage.getPhotoBytes(k))!;
      }
    }
    final reviewer = await _seed(profile: false, scenario: 'over');
    await reviewer.setProfile(me);
    final senders = [staff.profile!, _otherStaff];
    for (var i = 0; i < reports.length; i++) {
      var p = buildReport(staff: senders[i], settings: staff.settings, month: month, trips: trips, photos: photos);
      p = _signSteps(p, reports[i]);
      await reviewer.storage.saveReport(p, photos: photos);
      reviewer.reports = [...reviewer.reports, p];
    }
    return reviewer;
  });
  return s!;
}

/// Lets file reads that started while building a screen finish, then draws the result.
Future<void> _settleReal(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
  await tester.pump();
  await tester.pumpAndSettle();
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
  // Reduced motion: looping animations (aurora, live dot) hold still so the frame can settle.
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _shotKey,
      child: ChangeNotifierProvider<AppState>.value(
        value: state,
        child: VehicleLogApp(themeMode: mode, splash: false),
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
    for (final r in state.reports) {
      for (final k in r.photoHashes.keys) {
        await precacheImage(FileImage(state.storage.reportPhotoFile(r, k)), ctx);
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
    await tester.pumpAndSettle();
  }
}

// ---------------------------------------------------------------- tests

void main() {
  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  testWidgets('opening animation', (tester) async {
    final s = await _state(tester, scenario: 'open');
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = _phone;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _shotKey,
        child: ChangeNotifierProvider<AppState>.value(value: s, child: const VehicleLogApp(themeMode: ThemeMode.light)),
      ),
    );
    var elapsed = 0;
    for (final ms in [0, 500, 900, 1500, 2400]) {
      await tester.pump(Duration(milliseconds: ms - elapsed));
      elapsed = ms;
      await _shot(tester, '00_splash_$ms');
    }
    // It hands over to the app by itself.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(NavigationBar), findsOneWidget);
  }, skip: !_enabled);

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

  testWidgets('report not sent yet', (tester) async {
    final s = await _state(tester, scenario: 'over');
    await _pumpApp(tester, s, size: const Size(360, 3000));
    await _tab(tester, 'Report');
    await _shot(tester, '20_report_not_sent');
    await _tapText(tester, 'Send report for sign-off');
    expect(find.text('Seal and send'), findsOneWidget);
    await _shot(tester, '21_send_dialog');
    await _tapText(tester, 'Not yet');
    expect(find.text('Seal and send'), findsNothing);
  }, skip: !_enabled);

  testWidgets('report cannot be sent with a trip open', (tester) async {
    final s = await _state(tester, scenario: 'open');
    await _pumpApp(tester, s, size: const Size(360, 3000));
    await _tab(tester, 'Report');
    expect(find.textContaining('still open'), findsWidgets);
    await _shot(tester, '22_report_blocked');
  }, skip: !_enabled);

  testWidgets('report with the Block Integrator', (tester) async {
    final s = await _staffWithReport(tester, []);
    await _pumpApp(tester, s, size: const Size(360, 3000));
    await _tab(tester, 'Report');
    expect(find.text('With Block Integrator'), findsWidgets);
    expect(find.text('Send the file again'), findsWidgets);
    await _shot(tester, '23_report_sent');
  }, skip: !_enabled);

  testWidgets('report with the District Integrator', (tester) async {
    final s = await _staffWithReport(tester, ['bi', 'acc']);
    await _pumpApp(tester, s, size: const Size(360, 3000));
    await _tab(tester, 'Report');
    expect(find.text('With District Integrator'), findsWidgets);
    await _shot(tester, '24_report_progress');
  }, skip: !_enabled);

  testWidgets('report sent back', (tester) async {
    final s = await _staffWithReport(tester, ['bi-return']);
    await _pumpApp(tester, s, size: const Size(360, 3000));
    await _tab(tester, 'Report');
    expect(find.text('Send again'), findsWidgets);
    await _shot(tester, '25_report_returned');
    await _tab(tester, 'Today');
    expect(find.text('Returned'), findsWidgets);
  }, skip: !_enabled);

  testWidgets('report approved', (tester) async {
    final s = await _staffWithReport(tester, ['bi', 'acc', 'di']);
    await _pumpApp(tester, s, size: const Size(360, 3000));
    await _tab(tester, 'Report');
    expect(find.text('Approved'), findsWidgets);
    expect(find.text('Share the approved copy'), findsWidgets);
    await _shot(tester, '26_report_approved');
  }, skip: !_enabled);

  testWidgets('a month that was sent takes no new trips', (tester) async {
    final s = await _staffWithReport(tester, []);
    expect(s.monthLocked(currentMonth()), isTrue);
    await _pumpApp(tester, s);
    await _tapText(tester, 'Start a trip');
    expect(find.textContaining('is closed'), findsOneWidget);
    await _shot(tester, '27_form_month_closed');
  }, skip: !_enabled);

  testWidgets('review inbox', (tester) async {
    final s = await _reviewerWithReports(tester, _diPerson, [
      ['bi', 'acc'],
      ['bi'],
    ]);
    await _pumpApp(tester, s, size: _tall);
    await _tab(tester, 'Review');
    expect(find.byType(ReportTile), findsNWidgets(2));
    expect(find.text('Needs your sign-off'), findsOneWidget);
    await _shot(tester, '28_review_inbox');
  }, skip: !_enabled);

  testWidgets('review and sign as Block Integrator', (tester) async {
    final s = await _reviewerWithReports(tester, _biPerson, [[]]);
    await _pumpApp(tester, s);
    await _tab(tester, 'Review');
    await tester.tap(find.byType(ReportTile).first);
    await tester.pumpAndSettle();
    await _resize(tester, const Size(360, 4200));
    await _settleReal(tester);
    expect(find.text('Every check passed'), findsOneWidget);
    expect(find.text('Checked, send to Accountant'), findsWidgets);
    await _shot(tester, '29_review_bi');

    // Sending back needs a reason.
    await _tapText(tester, 'Send back to Jitendra');
    expect(find.text('Write why you are sending it back.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Signing asks first.
    await _tapText(tester, 'Checked, send to Accountant');
    expect(find.text('Mark as checked?'), findsOneWidget);
    await _shot(tester, '30_sign_dialog');
    await _tapText(tester, 'Not yet');
    expect(find.text('Mark as checked?'), findsNothing);
  }, skip: !_enabled);

  testWidgets('approve as District Integrator with the extra km', (tester) async {
    final s = await _reviewerWithReports(tester, _diPerson, [
      ['bi', 'acc'],
    ]);
    await _pumpApp(tester, s);
    await _tab(tester, 'Review');
    await tester.tap(find.byType(ReportTile).first);
    await tester.pumpAndSettle();
    await _resize(tester, const Size(360, 4200));
    await _settleReal(tester);
    expect(find.text('Approve'), findsWidgets);
    final sw = find.byType(Switch);
    if (sw.evaluate().isNotEmpty) {
      await tester.ensureVisible(sw);
      await tester.tap(sw);
      await tester.pumpAndSettle();
    }
    await _shot(tester, '31_review_di');
  }, skip: !_enabled);

  testWidgets('a report trip opens read only, with its photos', (tester) async {
    final s = await _reviewerWithReports(tester, _biPerson, [[]]);
    await _pumpApp(tester, s, size: _tall);
    await _tab(tester, 'Review');
    await tester.tap(find.byType(ReportTile).first);
    await tester.pumpAndSettle();
    await _settleReal(tester);
    await _tapText(tester, 'Chinchpada');
    expect(find.text('Add a note'), findsNothing);
    expect(find.text('Odometer'), findsOneWidget);
    await _shot(tester, '32_report_trip_detail');
  }, skip: !_enabled);

  testWidgets('review in the dark and at large text', (tester) async {
    final s = await _reviewerWithReports(tester, _biPerson, [[]]);
    await _pumpApp(tester, s, mode: ThemeMode.dark, textScale: 1.3);
    await _tab(tester, 'Review');
    await _shot(tester, '33_dark_review_inbox');
    await tester.tap(find.byType(ReportTile).first);
    await tester.pumpAndSettle();
    await _resize(tester, const Size(360, 5200));
    await _settleReal(tester);
    await _shot(tester, '34_dark_review_report');
  }, skip: !_enabled);
}
