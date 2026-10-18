import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import '../models/profile.dart';
import '../models/trip.dart';
import 'storage_service.dart';
import 'trip_rules.dart';

class AppState extends ChangeNotifier {
  final StorageService storage = StorageService();
  Profile? profile;
  AppSettings settings = AppSettings();
  List<Trip> trips = [];
  Map<String, dynamic> meta = {};
  bool ready = false;

  Future<void> init({Directory? photosDir}) async {
    await storage.init(photosDir: photosDir);
    profile = storage.getProfile();
    settings = storage.getSettings();
    trips = storage.getTrips();
    meta = storage.getMeta();
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

  Future<void> eraseAll() async {
    await storage.clearAll();
    profile = null;
    settings = AppSettings();
    trips = [];
    meta = {};
    notifyListeners();
  }
}
