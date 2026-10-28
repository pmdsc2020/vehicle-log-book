// The monthly report: sealing, passing from phone to phone, signing in order, and catching tampering.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vehicle_log_book/models/profile.dart';
import 'package:vehicle_log_book/models/report.dart';
import 'package:vehicle_log_book/models/trip.dart';
import 'package:vehicle_log_book/services/app_state.dart';
import 'package:vehicle_log_book/services/report_service.dart';
import 'package:vehicle_log_book/services/trip_rules.dart';

Profile _person(String id, String name, String role) =>
    Profile(id: id, name: name, designation: roleTitle(role), block: 'Shahada', role: role, created: '2026-10-01T00:00:00Z');

String roleTitle(String role) => role == 'staff' ? 'Field Officer' : stepRoleLabel(role);

final Profile staff = _person('S-1', 'Asha Pawar', 'staff');
final Profile bi = _person('B-1', 'Ravi Patil', 'bi');
final Profile bi2 = _person('B-2', 'Other Patil', 'bi');
final Profile acc = _person('A-1', 'Meena Shah', 'acc');
final Profile di = _person('D-1', 'Jitendra Sonawane', 'di');

List<int> _photo(String key) => utf8.encode('odometer photo $key');

class _Log {
  final List<Trip> chain = [];
  final Map<String, List<int>> photos = {};

  /// Adds a closed, locked trip at the end of the chain.
  Trip add(String id, String date, int open, int close) {
    final t = Trip(
      id: id,
      mode: 'full',
      date: date,
      month: date.substring(0, 7),
      project: 'NABARD',
      vehicle: 'MH39AB1234',
      vtype: 'Two wheeler',
      from: 'Nandurbar',
      to: 'Shahada',
      activity: 'Village meeting',
      task: 'Meeting with the village committee',
      start: Reading(km: open, photoKey: '${id}s', photoHash: hashBytes(_photo('${id}s')), at: isoAt(date, '09:00')),
      end: Reading(km: close, photoKey: '${id}e', photoHash: hashBytes(_photo('${id}e')), at: isoAt(date, '17:00')),
      km: close - open,
      status: 'closed',
      loggedAt: isoAt(date, '17:05'),
    );
    photos['${id}s'] = _photo('${id}s');
    photos['${id}e'] = _photo('${id}e');
    sealTrip(t, chain);
    chain.add(t);
    return t;
  }

  Map<String, List<int>> photosOf(List<Trip> trips) => {
        for (final t in trips) ...{
          '${t.id}s': photos['${t.id}s']!,
          '${t.id}e': photos['${t.id}e']!,
        },
      };
}

/// Three October trips: 200 + 250 + 150 = 600 km, so 100 km above the 500 km limit.
_Log _october() {
  final log = _Log();
  log.add('t1', '2026-10-03', 1000, 1200);
  log.add('t2', '2026-10-10', 1200, 1450);
  log.add('t3', '2026-10-20', 1450, 1600);
  return log;
}

ReportPackage _sent(_Log log, {List<Trip>? trips, String month = '2026-10'}) {
  final use = trips ?? log.chain;
  return buildReport(
    staff: staff,
    settings: AppSettings(),
    month: month,
    trips: use,
    photos: log.photosOf(use),
  );
}

Map<String, String> _hashes(_Log log, [List<Trip>? trips]) => hashPhotos(log.photosOf(trips ?? log.chain));

ReportPackage _clone(ReportPackage p) =>
    ReportPackage.fromJson(Map<String, dynamic>.from(jsonDecode(jsonEncode(p.toJson())) as Map));

ReportPackage _rebuild(
  ReportPackage p, {
  List<Trip>? trips,
  List<SignOff>? signoffs,
  ReportSummary? summary,
  String? contentHash,
}) =>
    ReportPackage(
      format: p.format,
      reportId: p.reportId,
      revision: p.revision,
      month: p.month,
      staff: p.staff,
      policy: p.policy,
      summary: summary ?? p.summary,
      submittedAt: p.submittedAt,
      replaces: p.replaces,
      trips: trips ?? p.trips,
      photoHashes: p.photoHashes,
      contentHash: contentHash ?? p.contentHash,
      signoffs: signoffs ?? p.signoffs,
    );

bool _bad(PackageCheck c, String part) => c.lines.any((l) => l.state == CheckState.bad && l.title.contains(part));

bool _warns(PackageCheck c, String part) => c.lines.any((l) => l.state == CheckState.warn && l.title.contains(part));

void main() {
  group('a sent report', () {
    test('passes every check and shows the right figures', () {
      final log = _october();
      final p = _sent(log);
      expect(p.summary.trips, 3);
      expect(p.summary.km, 600);
      expect(p.summary.within, 500);
      expect(p.summary.excess, 100);
      expect(p.summary.amount, 2000);
      expect(p.signoffs, hasLength(1));
      expect(p.signoffs.first.step, 'submit');
      final check = verifyReport(p, _hashes(log));
      expect(check.ok, isTrue, reason: check.problems.map((l) => l.title).join(', '));
      final st = statusOf(p);
      expect(st.stage, ReportStage.withBi);
      expect(st.done, 1);
      expect(st.nextStep, 'bi');
    });

    test('is not changed by notes added to the trips afterwards', () {
      final log = _october();
      final p = _sent(log);
      final before = p.contentHash;
      log.chain.first.notes = [Note(at: nowIso(), text: 'Added later')];
      expect(reportContentHash(p), before);
      expect(verifyReport(p, _hashes(log)).ok, isTrue);
    });

    test('cannot be sent while a trip is open or when nothing was finished', () {
      final log = _october();
      final open = Trip(
        id: 'open1',
        mode: 'start',
        date: '2026-10-25',
        month: '2026-10',
        project: 'NABARD',
        vehicle: 'MH39AB1234',
        from: 'A',
        to: 'B',
        activity: 'Other',
        task: 'x',
        start: Reading(km: 1600, at: isoAt('2026-10-25', '09:00')),
        loggedAt: isoAt('2026-10-25', '09:00'),
      );
      expect(reportBlocker([...log.chain, open]), contains('still open'));
      expect(reportBlocker(const []), contains('no finished trips'));
      expect(reportBlocker(log.chain), isNull);
    });
  });

  group('signing', () {
    test('goes Block Integrator, Accountant, District Integrator, and the figures follow', () {
      final log = _october();
      var p = _sent(log);
      final photos = _hashes(log);

      p = signReport(p, bi, decision: 'forward', remarks: 'Trips match the field diary.');
      expect(statusOf(p).stage, ReportStage.withAcc);
      expect(statusOf(p).done, 2);
      expect(verifyReport(p, photos).ok, isTrue);

      p = signReport(p, acc, decision: 'forward');
      expect(statusOf(p).stage, ReportStage.withDi);
      expect(statusOf(p).done, 3);
      expect(verifyReport(p, photos).ok, isTrue);

      final within = signReport(p, di, decision: 'approve');
      expect(statusOf(within).stage, ReportStage.approved);
      expect(statusOf(within).done, 4);
      expect(payableKm(within), 500);
      expect(payableAmount(within), 2000);

      final withExcess = signReport(p, di, decision: 'approve', excessApproved: true);
      expect(payableKm(withExcess), 600);
      expect(payableAmount(withExcess), 2400);
      expect(verifyReport(withExcess, photos).ok, isTrue);
      expect(withExcess.signoffs.map((s) => s.step).toList(), ['submit', 'bi', 'acc', 'di']);
    });

    test('a return stops the report and tells the staff member why', () {
      final log = _october();
      final p = signReport(_sent(log), bi, decision: 'return', remarks: 'The 10 Oct trip has no task details.');
      final st = statusOf(p);
      expect(st.stage, ReportStage.returned);
      expect(st.returnedAt, 1);
      expect(st.nextStep, isNull);
      expect(st.last!.remarks, contains('10 Oct'));
      expect(() => signReport(p, acc, decision: 'forward'), throwsA(isA<ReportError>()));
      expect(verifyReport(p, _hashes(log)).ok, isTrue);
    });

    test('keeps to the rules', () {
      final log = _october();
      final p = _sent(log);
      expect(() => signReport(p, acc, decision: 'forward'), throwsA(isA<ReportError>()), reason: 'Accountant cannot go first');
      expect(() => signReport(p, di, decision: 'approve'), throwsA(isA<ReportError>()), reason: 'DI cannot go first');
      expect(() => signReport(p, staff, decision: 'forward'), throwsA(isA<ReportError>()), reason: 'staff cannot sign');
      expect(() => signReport(p, bi, decision: 'return'), throwsA(isA<ReportError>()), reason: 'a return needs a reason');
      expect(() => signReport(p, bi, decision: 'approve'), throwsA(isA<ReportError>()), reason: 'BI cannot approve');

      // A reviewer who is also the sender cannot sign their own report.
      final own = _person('B-1', 'Ravi Patil', 'bi');
      final reviewerReport = buildReport(
        staff: own,
        settings: AppSettings(),
        month: '2026-10',
        trips: log.chain,
        photos: log.photosOf(log.chain),
      );
      expect(() => signReport(reviewerReport, own, decision: 'forward'), throwsA(isA<ReportError>()));

      // The km-above-limit decision is only kept when there are such km.
      final small = _Log()..add('s1', '2026-10-03', 100, 200);
      final sp = buildReport(staff: staff, settings: AppSettings(), month: '2026-10', trips: small.chain, photos: small.photos);
      final done = signReport(signReport(signReport(sp, bi, decision: 'forward'), acc, decision: 'forward'), di,
          decision: 'approve', excessApproved: true);
      expect(done.signoffs.last.excessApproved, isFalse);
    });
  });

  group('the file', () {
    test('survives packing and opening, and stays valid', () {
      final log = _october();
      final p = signReport(_sent(log), bi, decision: 'forward', remarks: 'Ok');
      final bytes = encodeReportFile(p, log.photosOf(log.chain));
      expect(bytes[0], 0x1f, reason: 'compressed');
      final file = decodeReportFile(bytes);
      expect(file.photos.keys.toSet(), log.photosOf(log.chain).keys.toSet());
      expect(jsonEncode(file.report.toJson()), jsonEncode(p.toJson()));
      expect(verifyReport(file.report, hashPhotos(file.photos)).ok, isTrue);
    });

    test('plain text copy opens too', () {
      final log = _october();
      final p = _sent(log);
      final plain = utf8.encode(jsonEncode({...p.toJson(), 'photos': {}}));
      expect(decodeReportFile(plain).report.reportId, p.reportId);
    });

    test('refuses things that are not reports', () {
      expect(() => decodeReportFile(const []), throwsA(isA<ReportError>()));
      expect(() => decodeReportFile(utf8.encode('hello')), throwsA(isA<ReportError>()));
      expect(() => decodeReportFile(utf8.encode('{"a":1}')), throwsA(isA<ReportError>()));
    });

    test('refuses photo names that could point outside the folder', () {
      final log = _october();
      final p = _sent(log);
      final bad = utf8.encode(jsonEncode({
        ...p.toJson(),
        'photos': {'../../evil': base64Encode([1, 2, 3])},
      }));
      expect(() => decodeReportFile(bad), throwsA(isA<ReportError>()));
      final badId = utf8.encode(jsonEncode({...p.toJson(), 'reportId': '../x', 'photos': {}}));
      expect(() => decodeReportFile(badId), throwsA(isA<ReportError>()));
    });
  });

  group('tampering is caught', () {
    test('a trip edited after it was locked', () {
      final log = _october();
      final c = _clone(_sent(log));
      c.trips[0].km = 999;
      final check = verifyReport(c, _hashes(log));
      expect(check.ok, isFalse);
      expect(_bad(check, 'seal'), isTrue);
      expect(_bad(check, 'fingerprint'), isTrue);
    });

    test('a note slipped into a trip', () {
      final log = _october();
      final c = _clone(_sent(log));
      c.trips[1].notes = [Note(at: nowIso(), text: 'Approved by DI verbally')];
      expect(_bad(verifyReport(c, _hashes(log)), 'fingerprint'), isTrue);
    });

    test('a meter photo swapped for another', () {
      final log = _october();
      final p = _sent(log);
      final swapped = {..._hashes(log), 't2s': hashBytes(utf8.encode('a different picture'))};
      final check = verifyReport(p, swapped);
      expect(check.ok, isFalse);
      expect(_bad(check, 'photos'), isTrue);
    });

    test('a meter photo left out of the file', () {
      final log = _october();
      final p = _sent(log);
      final fewer = {..._hashes(log)}..remove('t3e');
      expect(_bad(verifyReport(p, fewer), 'photos'), isTrue);
    });

    test('a trip taken out', () {
      final log = _october();
      final c = _clone(_sent(log));
      final fewer = _rebuild(c, trips: [c.trips[0], c.trips[2]]);
      final check = verifyReport(fewer, _hashes(log));
      expect(check.ok, isFalse);
    });

    test('a summary that does not follow from the trips, even when re-sealed', () {
      final log = _october();
      final honest = _sent(log);
      const lie = ReportSummary(trips: 3, km: 600, within: 600, excess: 0, amount: 2400);
      final bare = _rebuild(honest, summary: lie, contentHash: '', signoffs: const []);
      final content = reportContentHash(bare);
      final sealed = _rebuild(bare, contentHash: content);
      final first = SignOff(
        step: 'submit',
        userId: staff.id,
        name: staff.name,
        role: 'staff',
        at: honest.submittedAt,
        decision: 'sent',
        prevHash: content,
      );
      final forged = sealed.withSignoff(first.withHash(signoffHash(sealed, first)));
      final check = verifyReport(forged, _hashes(log));
      expect(check.ok, isFalse);
      expect(_bad(check, 'Figures'), isTrue);
    });

    test('a sign-off whose remarks were rewritten', () {
      final log = _october();
      final p = signReport(_sent(log), bi, decision: 'return', remarks: 'Fix the 10 Oct trip.');
      final c = _clone(p);
      final b = c.signoffs[1];
      final edited = SignOff(
        step: b.step,
        userId: b.userId,
        name: b.name,
        designation: b.designation,
        role: b.role,
        at: b.at,
        decision: b.decision,
        remarks: 'All fine.',
        prevHash: b.prevHash,
        hash: b.hash,
      );
      final check = verifyReport(_rebuild(c, signoffs: [c.signoffs[0], edited]), _hashes(log));
      expect(_bad(check, 'Sign-offs'), isTrue);
    });

    test('a sign-off taken out of the middle', () {
      final log = _october();
      var p = _sent(log);
      p = signReport(p, bi, decision: 'forward');
      p = signReport(p, acc, decision: 'forward');
      final skipped = _rebuild(p, signoffs: [p.signoffs[0], p.signoffs[2]]);
      expect(_bad(verifyReport(skipped, _hashes(log)), 'Sign-offs'), isTrue);
    });

    test('a sign-off added after the report was returned', () {
      final log = _october();
      final returned = signReport(_sent(log), bi, decision: 'return', remarks: 'Fix it.');
      final extra = SignOff(
        step: 'acc',
        userId: acc.id,
        name: acc.name,
        role: 'acc',
        at: nowIso(),
        decision: 'forward',
        prevHash: returned.signoffs.last.hash,
      );
      final more = returned.withSignoff(extra.withHash(signoffHash(returned, extra)));
      expect(_bad(verifyReport(more, _hashes(log)), 'Sign-offs'), isTrue);
    });

    test('the staff member signing as a reviewer', () {
      final log = _october();
      final p = _sent(log);
      final self = SignOff(
        step: 'bi',
        userId: staff.id,
        name: 'Asha Pawar',
        role: 'bi',
        at: nowIso(),
        decision: 'forward',
        prevHash: p.signoffs.last.hash,
      );
      final forged = p.withSignoff(self.withHash(signoffHash(p, self)));
      expect(_bad(verifyReport(forged, _hashes(log)), 'Sign-offs'), isTrue);
    });
  });

  group('entries around the month', () {
    test('a gap from another month is flagged but not fatal', () {
      final log = _Log();
      final a = log.add('t1', '2026-10-30', 100, 150);
      log.add('n1', '2026-11-01', 150, 180); // a November entry locked in between
      final c = log.add('t2', '2026-10-31', 180, 230);
      final p = _sent(log, trips: [a, c]);
      final check = verifyReport(p, _hashes(log, [a, c]));
      expect(check.ok, isTrue);
      expect(_warns(check, 'not in this report'), isTrue);
    });

    test('the month continues from the month before', () {
      final log = _Log();
      final sep = log.add('s1', '2026-09-28', 100, 150);
      final o1 = log.add('o1', '2026-10-02', 150, 200);
      final o2 = log.add('o2', '2026-10-05', 200, 260);
      final sepReport = _sent(log, trips: [sep], month: '2026-09');
      final octReport = _sent(log, trips: [o1, o2]);
      final check = verifyReport(octReport, _hashes(log, [o1, o2]), previous: sepReport);
      expect(check.ok, isTrue);
      expect(check.lines.any((l) => l.state == CheckState.ok && l.title.contains('Continues')), isTrue);
    });

    test('entries missing between two months are flagged', () {
      final log = _Log();
      final sep = log.add('s1', '2026-09-28', 100, 150);
      log.add('s2', '2026-09-29', 150, 170); // left out of the September report
      final o1 = log.add('o1', '2026-10-02', 170, 200);
      final sepReport = _sent(log, trips: [sep], month: '2026-09');
      final octReport = _sent(log, trips: [o1]);
      final check = verifyReport(octReport, _hashes(log, [o1]), previous: sepReport);
      expect(_warns(check, 'earlier month'), isTrue);
    });

    test('months step back and forward', () {
      expect(shiftMonth('2026-01', -1), '2025-12');
      expect(shiftMonth('2026-12', 1), '2027-01');
      expect(shiftMonth('2026-10', -1), '2026-09');
    });
  });

  group('on the phones', () {
    Future<AppState> device(String name, Profile who, {Directory? dir}) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final a = AppState();
      await a.init(photosDir: dir ?? Directory.systemTemp.createTempSync('vlb_${name}_'));
      await a.setProfile(who);
      return a;
    }

    Future<AppState> staffPhone() async {
      final a = await device('staff', staff);
      final log = _october();
      for (final t in log.chain) {
        await a.addOrUpdateTrip(t);
      }
      for (final e in log.photos.entries) {
        await a.storage.savePhoto(e.key, e.value);
      }
      return a;
    }

    Future<List<int>> fileOf(AppState a, ReportPackage p) async {
      final f = await a.exportReport(p, dir: Directory.systemTemp.createTempSync('vlb_out_'));
      expect(f.path.endsWith('.$reportFileExt'), isTrue);
      return f.readAsBytes();
    }

    test('the report goes round the office and comes back approved', () async {
      final a = await staffPhone();
      expect(a.monthLocked('2026-10'), isFalse);
      final sent = await a.submitReport('2026-10');
      expect(a.monthLocked('2026-10'), isTrue);
      await expectLater(a.submitReport('2026-10'), throwsA(isA<ReportError>()));
      final f1 = await fileOf(a, sent);

      final b = await device('bi', bi);
      final r1 = await b.importReport(f1);
      expect(r1.kind, ImportKind.added);
      expect((await b.checkReport(r1.report!)).ok, isTrue);
      expect((await b.importReport(f1)).kind, ImportKind.alreadyHave);
      expect(b.received, hasLength(1));
      final byBi = await b.signReportAs(r1.report!, decision: 'forward', remarks: 'Checked against the field diary.');
      final f2 = await fileOf(b, byBi);

      // The file coming back to the staff member moves the report along.
      final back = await a.importReport(f2);
      expect(back.kind, ImportKind.updated);
      expect(statusOf(a.myReport('2026-10')!).stage, ReportStage.withAcc);
      expect((await a.importReport(f1)).kind, ImportKind.alreadyHave, reason: 'an older file does not undo progress');
      expect(statusOf(a.myReport('2026-10')!).stage, ReportStage.withAcc);

      final c = await device('acc', acc);
      final r2 = await c.importReport(f2);
      expect(r2.kind, ImportKind.added);
      final byAcc = await c.signReportAs(r2.report!, decision: 'forward');
      final f3 = await fileOf(c, byAcc);

      final d = await device('di', di);
      final r3 = await d.importReport(f3);
      expect(r3.kind, ImportKind.added);
      expect((await d.checkReport(r3.report!)).ok, isTrue);
      final byDi = await d.signReportAs(r3.report!, decision: 'approve', excessApproved: true);
      final f4 = await fileOf(d, byDi);

      expect((await a.importReport(f4)).kind, ImportKind.updated);
      final finalReport = a.myReport('2026-10')!;
      expect(statusOf(finalReport).stage, ReportStage.approved);
      expect(payableAmount(finalReport), 2400);
      expect(finalReport.signoffs.map((s) => s.name).toList(), ['Asha Pawar', 'Ravi Patil', 'Meena Shah', 'Jitendra Sonawane']);
      expect((await a.checkReport(finalReport)).ok, isTrue);
    });

    test('keeps reports after the app is closed and opened again', () async {
      final dir = Directory.systemTemp.createTempSync('vlb_keep_');
      final a = await device('keep', bi, dir: dir);
      final staffApp = await staffPhone();
      final bytes = await fileOf(staffApp, await staffApp.submitReport('2026-10'));
      expect((await a.importReport(bytes)).kind, ImportKind.added);

      final again = AppState();
      await again.init(photosDir: dir);
      expect(again.reports, hasLength(1));
      expect((await again.checkReport(again.reports.first)).ok, isTrue);
    });

    test('turns away files it should not keep', () async {
      final staffApp = await staffPhone();
      final bytes = await fileOf(staffApp, await staffApp.submitReport('2026-10'));

      final colleague = await device('colleague', _person('S-2', 'Other Staff', 'staff'));
      expect((await colleague.importReport(bytes)).kind, ImportKind.notYours);
      expect(colleague.reports, isEmpty);

      final reviewer = await device('bi2', bi);
      expect((await reviewer.importReport(utf8.encode('not a report'))).kind, ImportKind.invalid);

      final file = decodeReportFile(bytes);
      final tampered = _clone(file.report);
      tampered.trips[0].km = 5;
      final outcome = await reviewer.importReport(encodeReportFile(tampered, file.photos));
      expect(outcome.kind, ImportKind.rejected);
      expect(outcome.check!.ok, isFalse);
      expect(reviewer.reports, isEmpty, reason: 'a failed file is not kept');
    });

    test('two different signatures on the same step are a conflict', () async {
      final staffApp = await staffPhone();
      final f1 = await fileOf(staffApp, await staffApp.submitReport('2026-10'));

      final first = await device('biA', bi);
      final onePkg = (await first.importReport(f1)).report!;
      final signedA = await first.signReportAs(onePkg, decision: 'forward', remarks: 'Ok');
      final fA = await fileOf(first, signedA);

      final second = await device('biB', bi2);
      final twoPkg = (await second.importReport(f1)).report!;
      final signedB = await second.signReportAs(twoPkg, decision: 'return', remarks: 'No');
      final fB = await fileOf(second, signedB);

      expect((await staffApp.importReport(fA)).kind, ImportKind.updated);
      expect((await staffApp.importReport(fB)).kind, ImportKind.conflict);
      expect((await first.importReport(fB)).kind, ImportKind.conflict);
    });

    test('a returned report can be fixed and sent again as a new version', () async {
      final staffApp = await staffPhone();
      final v1 = await staffApp.submitReport('2026-10');
      final f1 = await fileOf(staffApp, v1);

      final b = await device('bi', bi);
      final imported = (await b.importReport(f1)).report!;
      final returned = await b.signReportAs(imported, decision: 'return', remarks: 'Add the purpose of the 10 Oct trip.');
      final f2 = await fileOf(b, returned);

      expect((await staffApp.importReport(f2)).kind, ImportKind.updated);
      expect(statusOf(staffApp.myReport('2026-10')!).stage, ReportStage.returned);
      expect(staffApp.monthLocked('2026-10'), isFalse, reason: 'the month opens again');

      // The staff member adds a note and sends again.
      final t = staffApp.trips.firstWhere((x) => x.id == 't2');
      await staffApp.addNote(t, 'Meeting was about the water committee.');
      final v2 = await staffApp.submitReport('2026-10');
      expect(v2.revision, 2);
      expect(v2.reportId, v1.reportId);
      expect(v2.replaces, isNotNull);
      expect(v2.replaces!.remarks, contains('purpose'));
      expect(v2.trips.firstWhere((x) => x.id == 't2').notes, hasLength(1));
      expect(staffApp.monthLocked('2026-10'), isTrue);
      expect((await staffApp.checkReport(v2)).ok, isTrue);

      final f3 = await fileOf(staffApp, v2);
      expect((await b.importReport(f3)).kind, ImportKind.added);
      expect(b.received, hasLength(1));
      expect(b.received.first.revision, 2, reason: 'the inbox shows the newest version');
    });
  });
}
