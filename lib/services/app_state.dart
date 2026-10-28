import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/profile.dart';
import '../models/report.dart';
import '../models/trip.dart';
import 'report_service.dart';
import 'storage_service.dart';
import 'trip_rules.dart';

enum ImportKind { added, updated, alreadyHave, conflict, notYours, invalid, rejected }

/// What happened when a report file was opened.
class ImportOutcome {
  final ImportKind kind;
  final ReportPackage? report;
  final PackageCheck? check;
  final String message;
  const ImportOutcome(this.kind, {this.report, this.check, this.message = ''});

  /// The report is on this phone and can be shown.
  bool get opened => kind == ImportKind.added || kind == ImportKind.updated || kind == ImportKind.alreadyHave;
}

class AppState extends ChangeNotifier {
  final StorageService storage = StorageService();
  Profile? profile;
  AppSettings settings = AppSettings();
  List<Trip> trips = [];
  Map<String, dynamic> meta = {};

  /// Month reports on this phone: ones this person sent and ones sent to them to sign.
  List<ReportPackage> reports = [];
  bool ready = false;

  Future<void> init({Directory? photosDir, Directory? reportsDir}) async {
    await storage.init(photosDir: photosDir, reportsDir: reportsDir);
    profile = storage.getProfile();
    settings = storage.getSettings();
    trips = storage.getTrips();
    meta = storage.getMeta();
    reports = await storage.loadReports();
    ready = true;
    notifyListeners();
  }

  Future<void> setProfile(Profile p) async {
    profile = p;
    await storage.saveProfile(p);
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings s) async {
    settings = s;
    await storage.saveSettings(s);
    notifyListeners();
  }

  /// Projects and types of work offered on the trip form. Trips already saved keep their own names.
  Future<void> setProjects(List<String> v) async {
    settings.projects = List<String>.of(v);
    await updateSettings(settings);
  }

  Future<void> setActivities(List<String> v) async {
    settings.activities = List<String>.of(v);
    await updateSettings(settings);
  }

  Future<void> addOrUpdateTrip(Trip t) async {
    await storage.saveTrip(t);
    trips = storage.getTrips();
    notifyListeners();
  }

  /// Saves a new trip. A trip that is already closed is locked (sealed) first.
  Future<void> createTrip(Trip t) async {
    if (t.status == 'closed') sealTrip(t, trips);
    await addOrUpdateTrip(t);
  }

  /// Adds the closing reading to an open trip and locks it.
  Future<void> closeTrip(Trip t, Reading end, {Map<String, dynamic>? prior}) async {
    t.end = end;
    t.km = end.km - t.start.km;
    t.status = 'closed';
    if (prior != null) t.prior = prior;
    sealTrip(t, trips);
    await addOrUpdateTrip(t);
  }

  /// A cancelled trip stays in the log book, locked, with 0 km.
  Future<void> cancelTrip(Trip t, String reason) async {
    t.status = 'cancelled';
    t.km = 0;
    t.cancel = {'reason': reason, 'at': nowIso()};
    sealTrip(t, trips);
    await addOrUpdateTrip(t);
  }

  Future<void> rememberChoices(Map<String, dynamic> changes) async {
    meta = {...meta, ...changes};
    await storage.saveMeta(meta);
  }

  /// Light, dark or follow the phone. Kept with the other remembered choices.
  ThemeMode get themeMode {
    switch (meta['theme']) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(String mode) async {
    meta = {...meta, 'theme': mode};
    await storage.saveMeta(meta);
    notifyListeners();
  }

  /// A locked trip can still get notes. Notes are not part of the seal.
  Future<void> addNote(Trip t, String text) async {
    t.notes = [...t.notes, Note(at: nowIso(), text: text)];
    await addOrUpdateTrip(t);
  }

  List<Trip> tripsOfMonth(String month) =>
      trips.where((t) => t.month == month).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  /// Newest trips first, across all months.
  List<Trip> recentTrips(int n) {
    final all = trips.where((t) => t.status != 'cancelled').toList()..sort((a, b) => tripOrder(b, a));
    return all.length > n ? all.sublist(0, n) : all;
  }

  Trip? openTrip() => trips.cast<Trip?>().firstWhere(
        (t) => t?.status == 'open',
        orElse: () => null,
      );

  // ---------------------------------------------------------------- month reports

  ReportPackage? reportByKey(String key) {
    for (final r in reports) {
      if (r.key == key) return r;
    }
    return null;
  }

  /// This person's own report for the month: the latest version sent.
  ReportPackage? myReport(String month) {
    final me = profile;
    if (me == null) return null;
    ReportPackage? best;
    for (final r in reports) {
      if (r.staff.id != me.id || r.month != month) continue;
      if (best == null || r.revision > best.revision) best = r;
    }
    return best;
  }

  /// A month that has been sent for sign-off takes no new entries, unless it came back.
  bool monthLocked(String month) {
    final r = myReport(month);
    return r != null && statusOf(r).stage != ReportStage.returned;
  }

  /// Other people's reports held here, the latest version of each, newest activity first.
  List<ReportPackage> get received {
    final me = profile;
    final latest = <String, ReportPackage>{};
    for (final r in reports) {
      if (me != null && r.staff.id == me.id) continue;
      final have = latest[r.reportId];
      if (have == null || r.revision > have.revision) latest[r.reportId] = r;
    }
    final out = latest.values.toList()
      ..sort((a, b) => (b.signoffs.isEmpty ? '' : b.signoffs.last.at).compareTo(a.signoffs.isEmpty ? '' : a.signoffs.last.at));
    return out;
  }

  /// The same person's report for the month before, if this phone holds it.
  ReportPackage? previousReportOf(ReportPackage p) {
    final before = shiftMonth(p.month, -1);
    ReportPackage? best;
    for (final r in reports) {
      if (r.staff.id != p.staff.id || r.month != before) continue;
      if (best == null || r.revision > best.revision) best = r;
    }
    return best;
  }

  /// Seals the month's trips and photos into a report and signs it as sent.
  /// Throws [ReportError] when it cannot be sent yet.
  Future<ReportPackage> submitReport(String month) async {
    final me = profile!;
    final monthTrips = tripsOfMonth(month);
    final blocker = reportBlocker(monthTrips);
    if (blocker != null) throw ReportError(blocker);
    final prev = myReport(month);
    if (prev != null && statusOf(prev).stage != ReportStage.returned) {
      throw const ReportError('This month has already been sent for sign-off.');
    }
    final photos = <String, List<int>>{};
    for (final t in monthTrips) {
      for (final k in photoKeysOf(t)) {
        if (photos.containsKey(k)) continue;
        final b = await storage.getPhotoBytes(k);
        if (b == null) {
          throw ReportError('The meter photo for the trip on ${fmtDate(t.date)} to ${t.to} is not on this phone, so the report cannot be sent.');
        }
        photos[k] = b;
      }
    }
    final pkg = buildReport(
      staff: me,
      settings: settings,
      month: month,
      trips: monthTrips,
      photos: photos,
      revision: (prev?.revision ?? 0) + 1,
      replaces: prev == null ? null : ReturnedNote.of(prev.revision, statusOf(prev).last!),
      reportId: prev?.reportId,
    );
    await storage.saveReport(pkg, photos: photos);
    reports = [...reports, pkg];
    notifyListeners();
    return pkg;
  }

  /// Opens a report file received from someone. Checks it before keeping it.
  Future<ImportOutcome> importReport(List<int> bytes) async {
    final me = profile!;
    final ReportFile file;
    try {
      file = decodeReportFile(bytes);
    } on ReportError catch (e) {
      return ImportOutcome(ImportKind.invalid, message: e.message);
    }
    final p = file.report;
    if (p.staff.id != me.id && stepOfRole(me.role) == null) {
      return ImportOutcome(
        ImportKind.notYours,
        report: p,
        message: 'This report is ${p.staff.name}\'s. Only the Block Integrator, Accountant and District Integrator open other people\'s reports.',
      );
    }
    final check = verifyReport(p, hashPhotos(file.photos), previous: previousReportOf(p));
    if (!check.ok) {
      return ImportOutcome(ImportKind.rejected, report: p, check: check, message: 'This file does not pass the checks, so it was not kept.');
    }
    final i = reports.indexWhere((r) => r.key == p.key);
    if (i < 0) {
      await storage.saveReport(p, photos: file.photos);
      reports = [...reports, p];
      notifyListeners();
      return ImportOutcome(ImportKind.added, report: p, check: check);
    }
    final have = reports[i];
    var same = have.contentHash == p.contentHash;
    final common = math.min(have.signoffs.length, p.signoffs.length);
    for (var k = 0; k < common && same; k++) {
      if (have.signoffs[k].hash != p.signoffs[k].hash) same = false;
    }
    if (!same) {
      return ImportOutcome(
        ImportKind.conflict,
        report: have,
        message: 'This file was signed differently from the copy already on this phone. Ask the sender for the latest file.',
      );
    }
    if (p.signoffs.length > have.signoffs.length) {
      await storage.saveReport(p, photos: file.photos);
      final next = [...reports];
      next[i] = p;
      reports = next;
      notifyListeners();
      return ImportOutcome(ImportKind.updated, report: p, check: check);
    }
    return ImportOutcome(ImportKind.alreadyHave, report: have, check: check);
  }

  /// Signs the report as this person and keeps the signed copy.
  Future<ReportPackage> signReportAs(
    ReportPackage p, {
    required String decision,
    String remarks = '',
    bool excessApproved = false,
  }) async {
    final signed = signReport(p, profile!, decision: decision, remarks: remarks, excessApproved: excessApproved);
    await storage.saveReport(signed);
    final i = reports.indexWhere((r) => r.key == p.key);
    final next = [...reports];
    if (i >= 0) {
      next[i] = signed;
    } else {
      next.add(signed);
    }
    reports = next;
    notifyListeners();
    return signed;
  }

  final Map<String, PackageCheck> _checks = {};

  /// Runs every check on a report held here, reading the photos from this phone. The result is
  /// kept for the session, so opening the same report again is instant.
  Future<PackageCheck> checkReport(ReportPackage p) async {
    final key = '${p.key}:${p.signoffs.length}';
    final known = _checks[key];
    if (known != null) return known;
    final result = verifyReport(p, await storage.hashReportPhotos(p), previous: previousReportOf(p));
    _checks[key] = result;
    return result;
  }

  /// Writes the report and its photos to one file ready to share.
  Future<File> exportReport(ReportPackage p, {Directory? dir}) async {
    final photos = await storage.readReportPhotos(p);
    final bytes = encodeReportFile(p, photos);
    final d = dir ?? await getTemporaryDirectory();
    final f = File('${d.path}/${reportFileName(p)}');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  Future<void> eraseAll() async {
    await storage.clearAll();
    profile = null;
    settings = AppSettings();
    trips = [];
    meta = {};
    reports = [];
    _checks.clear();
    notifyListeners();
  }
}
