import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';
import '../models/report.dart';
import '../models/trip.dart';

class StorageService {
  static const _profileKey = 'profile';
  static const _settingsKey = 'settings';
  static const _tripsKey = 'trips';
  static const _monthsKey = 'months';
  static const _metaKey = 'meta';

  late SharedPreferences _prefs;
  late Directory _photosDir;
  late Directory _reportsDir;

  /// [photosDir] and [reportsDir] let tests keep their files in a temporary folder.
  Future<void> init({Directory? photosDir, Directory? reportsDir}) async {
    _prefs = await SharedPreferences.getInstance();
    if (photosDir != null) {
      _photosDir = photosDir;
      _reportsDir = reportsDir ?? Directory('${photosDir.path}_reports');
    } else {
      final docs = await getApplicationDocumentsDirectory();
      _photosDir = Directory('${docs.path}/photos');
      _reportsDir = reportsDir ?? Directory('${docs.path}/reports');
    }
    if (!await _photosDir.exists()) await _photosDir.create(recursive: true);
    if (!await _reportsDir.exists()) await _reportsDir.create(recursive: true);
  }

  Profile? getProfile() {
    final s = _prefs.getString(_profileKey);
    return s == null ? null : Profile.fromJson(jsonDecode(s));
  }

  Future<void> saveProfile(Profile p) => _prefs.setString(_profileKey, jsonEncode(p.toJson()));

  AppSettings getSettings() {
    final s = _prefs.getString(_settingsKey);
    return s == null ? AppSettings() : AppSettings.fromJson(jsonDecode(s));
  }

  Future<void> saveSettings(AppSettings s) => _prefs.setString(_settingsKey, jsonEncode(s.toJson()));

  List<Trip> getTrips() {
    final s = _prefs.getString(_tripsKey);
    if (s == null) return [];
    return (jsonDecode(s) as List).map((e) => Trip.fromJson(e)).toList();
  }

  Future<void> saveTrips(List<Trip> trips) =>
      _prefs.setString(_tripsKey, jsonEncode(trips.map((t) => t.toJson()).toList()));

  Future<void> saveTrip(Trip t) async {
    final all = getTrips();
    final i = all.indexWhere((x) => x.id == t.id);
    if (i >= 0) all[i] = t; else all.add(t);
    await saveTrips(all);
  }

  /// Small remembered choices (last project, vehicle, starting place, approver).
  Map<String, dynamic> getMeta() {
    final s = _prefs.getString(_metaKey);
    if (s == null) return {};
    return Map<String, dynamic>.from(jsonDecode(s) as Map);
  }

  Future<void> saveMeta(Map<String, dynamic> m) => _prefs.setString(_metaKey, jsonEncode(m));

  Map<String, dynamic> getMonths() {
    final s = _prefs.getString(_monthsKey);
    return s == null ? {} : jsonDecode(s) as Map<String, dynamic>;
  }

  Future<void> saveMonths(Map<String, dynamic> m) => _prefs.setString(_monthsKey, jsonEncode(m));

  Future<String> savePhoto(String key, List<int> bytes) async {
    final file = File('${_photosDir.path}/$key.jpg');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<List<int>?> getPhotoBytes(String key) async {
    final file = File('${_photosDir.path}/$key.jpg');
    if (await file.exists()) return file.readAsBytes();
    return null;
  }

  String photoPath(String key) => '${_photosDir.path}/$key.jpg';

  // ---------------------------------------------------------------- reports

  /// Every report held on this phone: the ones this person sent and the ones sent to them.
  Future<List<ReportPackage>> loadReports() async {
    final out = <ReportPackage>[];
    if (!await _reportsDir.exists()) return out;
    await for (final e in _reportsDir.list()) {
      if (e is! Directory) continue;
      final f = File('${e.path}/report.json');
      if (!await f.exists()) continue;
      try {
        out.add(ReportPackage.fromJson(Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map)));
      } catch (_) {
        // A damaged folder is skipped. The rest of the reports still open.
      }
    }
    return out;
  }

  /// Saves a report and, when given, its photos. The report file is replaced in one step.
  Future<void> saveReport(ReportPackage p, {Map<String, List<int>> photos = const {}}) async {
    final dir = Directory('${_reportsDir.path}/${p.key}');
    final photoDir = Directory('${dir.path}/photos');
    if (!await photoDir.exists()) await photoDir.create(recursive: true);
    for (final e in photos.entries) {
      await File('${photoDir.path}/${e.key}.jpg').writeAsBytes(e.value);
    }
    final tmp = File('${dir.path}/report.json.tmp');
    await tmp.writeAsString(jsonEncode(p.toJson()));
    await tmp.rename('${dir.path}/report.json');
  }

  File reportPhotoFile(ReportPackage p, String key) => File('${_reportsDir.path}/${p.key}/photos/$key.jpg');

  Future<Map<String, List<int>>> readReportPhotos(ReportPackage p) async {
    final out = <String, List<int>>{};
    for (final k in p.photoHashes.keys) {
      final f = reportPhotoFile(p, k);
      if (await f.exists()) out[k] = await f.readAsBytes();
    }
    return out;
  }

  /// SHA-256 of each report picture really on this phone.
  Future<Map<String, String>> hashReportPhotos(ReportPackage p) async {
    final out = <String, String>{};
    for (final k in p.photoHashes.keys) {
      final f = reportPhotoFile(p, k);
      if (await f.exists()) out[k] = sha256.convert(await f.readAsBytes()).toString();
    }
    return out;
  }

  String sha256String(String input) => sha256.convert(utf8.encode(input)).toString();

  Future<void> clearAll() async {
    await _prefs.clear();
    if (await _photosDir.exists()) await _photosDir.delete(recursive: true);
    await _photosDir.create(recursive: true);
    if (await _reportsDir.exists()) await _reportsDir.delete(recursive: true);
    await _reportsDir.create(recursive: true);
  }
}
