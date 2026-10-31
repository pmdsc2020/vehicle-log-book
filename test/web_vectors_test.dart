// Reports built with the phone's own code and saved as files. The desktop reviewer (web/) is tested
// against these, so the two programs always agree on seals, hashes and checks. The files are printed
// as "VEC <name> <base64>" lines; CI shows them on the run page.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_log_book/models/profile.dart';
import 'package:vehicle_log_book/models/report.dart';
import 'package:vehicle_log_book/models/trip.dart';
import 'package:vehicle_log_book/services/report_service.dart';
import 'package:vehicle_log_book/services/trip_rules.dart';

Profile _who(String id, String name, String role, String designation) => Profile(
      id: id,
      name: name,
      designation: designation,
      block: 'Shahada',
      district: 'Nandurbar',
      mobile: '9890000000',
      role: role,
      created: '2026-10-01T00:00:00Z',
    );

final Profile _asha = _who('DSC-NDB-014', 'Asha "Tai" Pawar', 'staff', 'Field Officer');
final Profile _sunil = _who('DSC-NDB-021', 'सुनील पवार', 'staff', 'Project Officer');
final Profile _bi = _who('DSC-BI-02', 'रमेश पाटील', 'bi', 'Block Integrator');
final Profile _acc = _who('DSC-AC-01', 'Meena Shah', 'acc', 'Accountant');
final Profile _di = _who('DSC-DI-01', 'Jitendra Sonawane', 'di', 'District Integrator');

List<int> _photo(String key) => utf8.encode('odometer photo $key, फोटो');

/// A month of locked trips, as the phone keeps them.
class _Month {
  final List<Trip> chain = [];
  final Map<String, List<int>> photos = {};

  Reading _reading(String key, int km, String at,
      {GpsPoint? gps, bool oldPhoto = false, int? prevKm, String? returnTo, String? remarks, String? photoTime}) {
    photos[key] = _photo(key);
    return Reading(
      km: km,
      photoKey: key,
      photoHash: hashBytes(_photo(key)),
      at: at,
      gps: gps,
      photoTime: photoTime,
      oldPhoto: oldPhoto,
      prevKm: prevKm,
      returnTo: returnTo,
      remarks: remarks,
    );
  }

  Trip add({
    required String id,
    required String date,
    required int open,
    required int close,
    String project = 'NABARD',
    String from = 'Nandurbar',
    String to = 'Shahada',
    String activity = 'Village meeting',
    String task = 'Meeting with the village committee',
    GpsPoint? gps,
    bool oldPhoto = false,
    int? prevKm,
    String? returnTo,
    String? remarks,
    Map<String, dynamic>? lateInfo,
    Map<String, dynamic>? meterReset,
    Map<String, dynamic>? prior,
    List<Note> notes = const [],
  }) {
    final t = Trip(
      id: id,
      mode: 'full',
      date: date,
      month: date.substring(0, 7),
      project: project,
      vehicle: 'MH39AB1234',
      vtype: 'Two wheeler',
      from: from,
      to: to,
      activity: activity,
      task: task,
      start: _reading('${id}s', open, isoAt(date, '09:00'),
          gps: gps, oldPhoto: oldPhoto, prevKm: prevKm, photoTime: isoAt(date, '08:58')),
      end: _reading('${id}e', close, isoAt(date, '17:00'), returnTo: returnTo, remarks: remarks),
      km: close - open,
      status: 'closed',
      late: lateInfo,
      meterReset: meterReset,
      prior: prior,
      notes: notes,
      loggedAt: isoAt(date, '17:05'),
    );
    sealTrip(t, chain);
    chain.add(t);
    return t;
  }

  Trip addCancelled({required String id, required String date, required int open, required String reason}) {
    final t = Trip(
      id: id,
      mode: 'start',
      date: date,
      month: date.substring(0, 7),
      project: 'Project SAHAS',
      vehicle: 'MH39AB1234',
      vtype: 'Two wheeler',
      from: 'Nandurbar',
      to: 'Navapur',
      activity: 'Monitoring visit',
      task: 'Visit called off',
      start: _reading('${id}s', open, isoAt(date, '09:00')),
      status: 'cancelled',
      cancel: {'reason': reason, 'at': isoAt(date, '10:00')},
      loggedAt: isoAt(date, '09:05'),
    );
    sealTrip(t, chain);
    chain.add(t);
    return t;
  }

  Map<String, List<int>> get all => {for (final e in photos.entries) e.key: e.value};
}

/// Report A: office rule 500 km at 4 a km, 600 km used. Awkward text everywhere on purpose.
(ReportPackage, Map<String, List<int>>) _reportA() {
  final m = _Month();
  m.add(
    id: 't1',
    date: '2026-10-03',
    open: 1000,
    close: 1200,
    project: 'ABF (Axis Bank Foundation)',
    to: 'Taloda, Bhagdari',
    task: 'Meeting with “PIC” members — 5 villages',
    gps: GpsPoint(lat: 21.0, lng: 74.2412345678, acc: 12),
    prevKm: 990,
    returnTo: 'Nandurbar',
    remarks: 'Rain "heavy" on the way\nreturned by the bypass',
  );
  m.add(
    id: 't2',
    date: '2026-10-10',
    open: 1200,
    close: 1450,
    to: 'Akkalkuwa',
    oldPhoto: true,
    lateInfo: {'reason': 'Forgot to log, phone was dead (बॅटरी संपली)'},
    notes: [Note(at: '2026-10-11T06:00:00.000Z', text: 'Receipt kept: <b>No. 42</b> & stamp \\ ok')],
  );
  m.addCancelled(id: 't3', date: '2026-10-15', open: 1450, reason: 'Visit called off \\ rain');
  m.add(
    id: 't4',
    date: '2026-10-20',
    open: 5000,
    close: 5150,
    to: 'Dhadgaon',
    activity: 'Survey / planning',
    meterReset: {'reason': 'Meter replaced 🚗'},
    prior: {'by': 'Mr. Patil (District Integrator)', 'date': '2026-10-19', 'mode': 'WhatsApp', 'ref': 'Message 10:05', 'none': false},
  );
  final p = buildReport(
    staff: _asha,
    settings: AppSettings(),
    month: '2026-10',
    trips: m.chain,
    photos: m.all,
    at: '2026-10-28T06:30:15.123Z',
  );
  return (p, m.all);
}

/// Report B: 300 km a project at 4.35 a km, so the amounts are not whole numbers.
(ReportPackage, Map<String, List<int>>, _Month) _reportB() {
  final m = _Month();
  m.add(id: 'u1', date: '2026-10-02', open: 2000, close: 2180, to: 'Shahada', task: 'First visit');
  m.add(id: 'u2', date: '2026-10-09', open: 2180, close: 2340, to: 'Taloda', task: 'Second visit');
  m.add(id: 'u3', date: '2026-10-16', open: 2340, close: 2430, project: 'Project SAHAS', to: 'Navapur', task: 'Solar survey');
  final p = buildReport(
    staff: _sunil,
    settings: AppSettings(limitKm: 300, rate: 4.35, scope: 'project', highKm: 100),
    month: '2026-10',
    trips: m.chain,
    photos: m.all,
    at: '2026-10-27T05:00:00.000Z',
  );
  return (p, m.all, m);
}

void main() {
  test('save reports built by the phone code, for the desktop reviewer tests', () {
    final out = <String, ReportPackage>{};
    final photos = <String, Map<String, List<int>>>{};

    final (a0, aPhotos) = _reportA();
    final a1 = signReport(a0, _bi, decision: 'forward', remarks: 'Trips match the diary. मीटर फोटो स्पष्ट आहेत. 👍', at: '2026-10-28T08:00:00.000Z');
    final a2 = signReport(a1, _acc, decision: 'forward', remarks: 'Km × rate checked against "vouchers"\\ok', at: '2026-10-28T09:15:30.250Z');
    final a3 = signReport(a2, _di, decision: 'approve', remarks: '', excessApproved: true, at: '2026-10-29T04:45:00.000Z');
    for (final e in {'a_sent': a0, 'a_bi': a1, 'a_acc': a2, 'a_approved': a3}.entries) {
      out[e.key] = e.value;
      photos[e.key] = aPhotos;
    }

    final (b0, bPhotos, bMonth) = _reportB();
    final b1 = signReport(b0, _bi, decision: 'return', remarks: 'The task of 2 Oct is unclear. "Explain" the work\nबद्दल सविस्तर लिहा 🙏', at: '2026-10-27T10:00:00.000Z');
    bMonth.chain[0].notes = [Note(at: '2026-10-27T12:00:00.000Z', text: 'Meeting with the gram sevak, details added')];
    final b2 = buildReport(
      staff: _sunil,
      settings: AppSettings(limitKm: 300, rate: 4.35, scope: 'project', highKm: 100),
      month: '2026-10',
      trips: bMonth.chain,
      photos: bMonth.all,
      revision: 2,
      replaces: ReturnedNote.of(1, b1.signoffs.last),
      reportId: b0.reportId,
      at: '2026-10-27T12:30:00.000Z',
    );
    final b3 = signReport(b2, _bi, decision: 'forward', remarks: 'Fine now', at: '2026-10-27T14:00:00.000Z');
    for (final e in {'b_sent': b0, 'b_returned': b1, 'b_r2_sent': b2, 'b_r2_bi': b3}.entries) {
      out[e.key] = e.value;
      photos[e.key] = bPhotos;
    }

    expect(statusOf(a3).stage, ReportStage.approved);
    expect(payableKm(a3), 600);
    expect(statusOf(b1).stage, ReportStage.returned);
    expect(b1.signoffs.last.step, 'bi');
    expect(b2.revision, 2);

    for (final e in out.entries) {
      final bytes = encodeReportFile(e.value, photos[e.key]!);
      final back = decodeReportFile(bytes);
      final check = verifyReport(back.report, hashPhotos(back.photos));
      expect(check.ok, isTrue, reason: '${e.key}: ${check.problems.map((l) => l.title).join(', ')}');
      // Printed for the desktop tests; the name comes first so it can be picked out of the log.
      // ignore: avoid_print
      print('VEC ${e.key} ${base64Encode(bytes)}');
    }
  });
}
