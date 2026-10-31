// Report files in test/fixtures/web: some made by the phone code (a_*, b_*), some signed or built by the
// desktop reviewer (web_*). The phone must accept every one of them, and carry on signing the desktop ones.
// Remake the desktop ones with `node web/test/make_fixtures.js`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_log_book/models/profile.dart';
import 'package:vehicle_log_book/models/report.dart';
import 'package:vehicle_log_book/services/report_service.dart';

ReportFile _open(String name) => decodeReportFile(File('test/fixtures/web/$name.vlbreport').readAsBytesSync());

PackageCheck _check(ReportFile f) => verifyReport(f.report, hashPhotos(f.photos));

String _why(PackageCheck c) => c.problems.map((l) => '${l.title}: ${l.detail}').join(' | ');

Profile _who(String id, String name, String role) =>
    Profile(id: id, name: name, designation: stepRoleLabel(role), role: role, created: '2026-10-01T00:00:00Z');

void main() {
  final dir = Directory('test/fixtures/web');
  final names = dir.existsSync()
      ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.$reportFileExt')).map((f) => f.uri.pathSegments.last.replaceAll('.$reportFileExt', '')).toList()..sort())
      : <String>[];

  test('the fixtures are there', () {
    expect(names.length, greaterThanOrEqualTo(16));
  });

  group('every report file passes the phone checks', () {
    for (final n in names) {
      test(n, () {
        final f = _open(n);
        final c = _check(f);
        expect(c.ok, isTrue, reason: _why(c));
      });
    }
  });

  group('signed on the desktop', () {
    test('approved, with the extra km', () {
      final r = _open('web_a_approved').report;
      expect(statusOf(r).stage, ReportStage.approved);
      expect(r.signoffs.map((s) => s.role).toList(), ['staff', 'bi', 'acc', 'di']);
      expect(r.signoffs[1].name, 'रमेश पाटील');
      expect(r.signoffs[2].remarks, 'Km × rate checked against "vouchers"\\ok\nsecond line');
      expect(approvalOf(r)!.excessApproved, isTrue);
      expect(payableKm(r), 600);
      expect(payableAmount(r), 2400.0);
    });

    test('signed in the browser: a sample report through all three people', () {
      final r = _open('web_ui_approved').report;
      expect(statusOf(r).stage, ReportStage.approved);
      expect(r.staff.name, 'Sample Staff');
      expect(r.signoffs.map((s) => s.role).toList(), ['staff', 'bi', 'acc', 'di']);
      expect(r.signoffs.map((s) => s.designation).toList().sublist(1), ['Block Integrator', 'Accountant', 'District Integrator']);
      expect(r.signoffs[1].remarks, contains('मीटर'));
      expect(r.summary.km, 675);
      expect(r.summary.excess, 175);
      expect(approvalOf(r)!.excessApproved, isTrue);
      expect(payableKm(r), 675);
      expect(payableAmount(r), 2700.0);
    });

    test('approved, only within the limit', () {
      final r = _open('web_a_approved_within').report;
      expect(statusOf(r).stage, ReportStage.approved);
      expect(approvalOf(r)!.excessApproved, isFalse);
      expect(payableKm(r), 500);
    });

    test('sent back by the Block Integrator, and by the Accountant', () {
      final b = _open('web_b_returned').report;
      expect(statusOf(b).stage, ReportStage.returned);
      expect(statusOf(b).last!.step, 'bi');
      expect(statusOf(b).last!.remarks, contains('More detail'));
      final a = _open('web_a_returned_by_acc').report;
      expect(statusOf(a).stage, ReportStage.returned);
      expect(statusOf(a).last!.step, 'acc');
    });

    test('version 2 of a report goes on to the District Integrator', () {
      final r = _open('web_b_r2_acc').report;
      expect(r.revision, 2);
      expect(r.replaces, isNotNull);
      expect(statusOf(r).stage, ReportStage.withDi);
    });

    test('the phone carries on signing a report the desktop started', () {
      final f = _open('web_built_bi');
      expect(statusOf(f.report).stage, ReportStage.withAcc);
      final withAcc = signReport(f.report, _who('P-AC', 'Phone Accountant', 'acc'), decision: 'forward', remarks: 'ok');
      final withDi = signReport(withAcc, _who('P-DI', 'Phone DI', 'di'), decision: 'approve', excessApproved: true);
      expect(statusOf(withDi).stage, ReportStage.approved);
      final c = verifyReport(withDi, hashPhotos(f.photos));
      expect(c.ok, isTrue, reason: _why(c));
      expect(payableKm(withDi), withDi.summary.within + withDi.summary.excess);
    });
  });

  group('built on the desktop', () {
    test('a sent report has the same figures the phone works out', () {
      final f = _open('web_built_sent');
      expect(f.report.summary.trips, 3);
      expect(f.report.summary.km, 600);
      expect(f.report.summary.within, 500);
      expect(f.report.summary.excess, 100);
      expect(f.report.summary.amount, 2000.0);
      expect(f.report.trips.first.start.gps!.lat, 21.0);
      expect(f.photos.length, 6);
    });
  });
}
