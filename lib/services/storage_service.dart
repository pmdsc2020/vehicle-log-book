import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';
import '../models/trip.dart';

class StorageService {
  static const _profileKey = 'profile';
  static const _settingsKey = 'settings';
  static const _tripsKey = 'trips';
  static const _monthsKey = 'months';
  static const _inboxKey = 'inbox';
  static const _metaKey = 'meta';

  late SharedPreferences _prefs;
  late Directory _photosDir;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final docs = await getApplicationDocumentsDirectory();
    _photosDir = Directory('${docs.path}/photos');
    if (!await _photosDir.exists()) await _photosDir.create(recursive: true);
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

  String sha256String(String input) => sha256.convert(utf8.encode(input)).toString();

  Future<void> clearAll() async {
    await _prefs.clear();
    if (await _photosDir.exists()) await _photosDir.delete(recursive: true);
    await _photosDir.create(recursive: true);
  }
}
