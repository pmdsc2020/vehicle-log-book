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

  Future<void> init() async {
    await storage.init();
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

  List<Trip> tripsOfMonth(String month) =>
      trips.where((t) => t.month == month).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

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
