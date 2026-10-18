import 'package:flutter/foundation.dart';
import '../models/profile.dart';
import '../models/trip.dart';
import 'storage_service.dart';

class AppState extends ChangeNotifier {
  final StorageService storage = StorageService();
  Profile? profile;
  AppSettings settings = AppSettings();
  List<Trip> trips = [];
  bool ready = false;

  Future<void> init() async {
    await storage.init();
    profile = storage.getProfile();
    settings = storage.getSettings();
    trips = storage.getTrips();
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
    notifyListeners();
  }
}
