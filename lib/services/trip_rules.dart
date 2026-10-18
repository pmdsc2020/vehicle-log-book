import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../models/profile.dart';
import '../models/trip.dart';

/// Ways a prior approval can be taken (same list as the HTML app).
const priorModes = ['Phone call', 'WhatsApp', 'Email', 'Written note', 'In person'];

// ---------------------------------------------------------------- dates

/// Current time as a UTC ISO string with millisecond precision (like JS toISOString).
String nowIso() =>
    DateTime.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch, isUtc: true)
        .toIso8601String();

String _two(int n) => n.toString().padLeft(2, '0');

String dateStr(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String todayStr() => dateStr(DateTime.now());

String monthOf(String date) => date.length >= 7 ? date.substring(0, 7) : date;

String addDays(String date, int n) {
  final d = DateTime.parse(date);
  return dateStr(DateTime(d.year, d.month, d.day + n));
}

/// Local date + "HH:mm" to a UTC ISO string.
String isoAt(String date, String hhmm) {
  final d = DateTime.parse(date);
  final parts = hhmm.split(':');
  final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  return DateTime(d.year, d.month, d.day, h, m).toUtc().toIso8601String();
}

/// Local calendar date (yyyy-MM-dd) of an ISO time.
String localDateOf(String iso) => dateStr(DateTime.parse(iso).toLocal());

/// dd-MM-yyyy from yyyy-MM-dd.
String fmtDate(String ymd) {
  final p = ymd.split('-');
  if (p.length != 3) return ymd;
  return '${p[2]}-${p[1]}-${p[0]}';
}

/// Whole number with Indian digit grouping: 1,23,456.
String fmtKm(num n) {
  final s = n.round().abs().toString();
  String out;
  if (s.length <= 3) {
    out = s;
  } else {
    final head = s.substring(0, s.length - 3);
    final tail = s.substring(s.length - 3);
    final buf = StringBuffer();
    for (var i = 0; i < head.length; i++) {
      if (i > 0 && (head.length - i) % 2 == 0) buf.write(',');
      buf.write(head[i]);
    }
    out = '${buf.toString()},$tail';
  }
  return n < 0 ? '-$out' : out;
}

final Random _rng = Random();

String uid(String prefix) =>
    '$prefix${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_rng.nextInt(1 << 30).toRadixString(36)}';

// ---------------------------------------------------------------- odometer rules

int tripOrder(Trip a, Trip b) {
  final c = a.date.compareTo(b.date);
  if (c != 0) return c;
  final d = a.start.at.compareTo(b.start.at);
  if (d != 0) return d;
  return a.start.km.compareTo(b.start.km);
}

/// The reading a trip leaves on the meter: closing if closed, else opening.
int readingOf(Trip t) => t.end != null ? t.end!.km : t.start.km;

class Neighbours {
  final Trip? prev;
  final Trip? next;
  const Neighbours(this.prev, this.next);
}

Neighbours neighbours(List<Trip> trips, String vehicle, String date, String atIso, String? excludeId) {
  final list = trips
      .where((t) => t.vehicle == vehicle && t.status != 'cancelled' && t.id != excludeId)
      .toList()
    ..sort(tripOrder);
  final key = '$date|$atIso';
  Trip? prev;
  Trip? next;
  for (final t in list) {
    if ('${t.date}|${t.start.at}'.compareTo(key) <= 0) {
      prev = t;
    } else {
      next = t;
      break;
    }
  }
  return Neighbours(prev, next);
}

class ReadingCheck {
  final Map<String, String> errs;
  final Trip? prev;
  final Trip? next;
  final int? prevKm;

  /// Km between the last logged reading and this opening reading (not logged by anyone).
  final int gap;
  const ReadingCheck(this.errs, this.prev, this.next, this.prevKm, this.gap);
}

/// Readings must move forward trip after trip on the same vehicle.
ReadingCheck checkReadings({
  required List<Trip> trips,
  required String vehicle,
  required String date,
  required String atIso,
  required int? open,
  int? close,
  String? excludeId,
  bool reset = false,
}) {
  final errs = <String, String>{};
  final nb = neighbours(trips, vehicle, date, atIso, excludeId);
  final prev = nb.prev;
  final next = nb.next;
  final prevKm = prev == null ? null : readingOf(prev);

  if (open == null || open < 0) {
    errs['okm'] = 'Enter the opening reading from the meter.';
  } else if (open > 9999999) {
    errs['okm'] = 'This reading looks too large. Check the digits.';
  } else if (prev != null && prev.status == 'open' && !reset) {
    errs['okm'] = 'A trip on this vehicle is still open (${fmtDate(prev.date)}). End or cancel it first.';
  } else if (!reset && prev != null && prevKm != null && open < prevKm) {
    errs['okm'] = 'Opening reading is below the last reading, ${fmtKm(prevKm)} km on '
        '${fmtDate(prev.date)}. Check the meter, or tick "Meter was reset or replaced".';
  }

  if (close != null && !errs.containsKey('okm')) {
    final o = open ?? 0;
    if (close < 0) {
      errs['ckm'] = 'Enter the closing reading from the meter.';
    } else if (close <= o) {
      errs['ckm'] = 'Closing reading must be more than the opening reading.';
    } else if (!reset && next != null && close > next.start.km) {
      errs['ckm'] = 'Closing reading is above the opening reading of the next trip, '
          '${fmtKm(next.start.km)} km on ${fmtDate(next.date)}.';
    }
  }

  var gap = 0;
  if (open != null && prev != null && prevKm != null && open >= prevKm && prev.status != 'open') {
    gap = open - prevKm;
  }
  return ReadingCheck(errs, prev, next, prevKm, gap);
}

/// Km already used this month by closed trips (per project if the office rule says so).
int usedKm(List<Trip> trips, AppSettings s, String month, String project, String? excludeId) {
  var sum = 0;
  for (final t in trips) {
    if (t.month != month || t.status != 'closed' || t.id == excludeId) continue;
    if (s.scope == 'project' && t.project != project) continue;
    sum += t.km ?? 0;
  }
  return sum;
}

// ---------------------------------------------------------------- locking (hash chain)

dynamic _gpsKey(GpsPoint? g) => g == null ? '' : [g.lat, g.lng, g.acc];

/// The fields a seal covers. Same layout as coreOf() in the HTML app.
List<dynamic> coreOf(Trip t) {
  final s = t.start;
  final e = t.end;
  final lateInfo = t.late;
  final reset = t.meterReset;
  final prior = t.prior;
  final cancel = t.cancel;
  return <dynamic>[
    t.id,
    t.chainPos,
    t.date,
    t.project,
    t.vehicle,
    t.from,
    t.to,
    t.activity,
    t.task,
    t.mode,
    <dynamic>[s.km, s.photoHash ?? '', s.at, _gpsKey(s.gps), s.photoTime ?? '', s.prevKm ?? ''],
    e == null
        ? ''
        : <dynamic>[e.km, e.photoHash ?? '', e.at, _gpsKey(e.gps), e.photoTime ?? '', e.returnTo ?? '', e.remarks ?? ''],
    t.km,
    t.status,
    lateInfo == null ? '' : (lateInfo['reason'] ?? ''),
    reset == null ? '' : (reset['reason'] ?? ''),
    prior == null
        ? ''
        : <dynamic>[prior['by'] ?? '', prior['date'] ?? '', prior['mode'] ?? '', prior['ref'] ?? '', prior['none'] == true],
    cancel == null ? '' : <dynamic>[cancel['reason'] ?? '', cancel['at'] ?? ''],
    t.loggedAt,
    t.prevHash ?? '',
  ];
}

String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();

String hashTrip(Trip t) => sha256Hex(jsonEncode(coreOf(t)));

/// Locks a trip: puts it in the chain after the last locked trip and stamps its hash.
void sealTrip(Trip t, List<Trip> all) {
  Trip? last;
  for (final x in all) {
    if (x.id == t.id) continue;
    final p = x.chainPos;
    if (p != null && (last == null || p > (last.chainPos ?? 0))) last = x;
  }
  t.chainPos = (last?.chainPos ?? 0) + 1;
  t.prevHash = last?.hash ?? '';
  t.lockedAt = nowIso();
  t.hash = hashTrip(t);
}

/// True when a locked trip still matches its seal.
bool sealIntact(Trip t) => t.hash != null && t.hash == hashTrip(t);

// ---------------------------------------------------------------- amounts and summaries

/// Rupees with Indian grouping. Paise show only when there are any.
String fmtRs(num n) {
  var whole = n.floor();
  var paise = ((n - whole) * 100).round();
  if (paise >= 100) {
    whole += 1;
    paise = 0;
  }
  final head = '₹${fmtKm(whole)}';
  return paise == 0 ? head : '$head.${paise.toString().padLeft(2, '0')}';
}

/// Totals for one month of one person's trips.
class MonthSummary {
  final int trips;

  /// All km on closed trips.
  final int km;

  /// Km inside the monthly limit (limit applies per project if the office rule says so).
  final int within;

  /// Km above the limit. Paid only after District Integrator approval.
  final int excess;

  /// Rupees for the km inside the limit.
  final double amount;

  /// The figure the gauge compares with the limit.
  final int gaugeKm;
  final Map<String, int> kmByProject;
  final Map<String, int> tripsByProject;

  const MonthSummary({
    required this.trips,
    required this.km,
    required this.within,
    required this.excess,
    required this.amount,
    required this.gaugeKm,
    required this.kmByProject,
    required this.tripsByProject,
  });
}

MonthSummary summarise(List<Trip> monthTrips, AppSettings s) {
  final kmBy = <String, int>{};
  final countBy = <String, int>{};
  var km = 0;
  var trips = 0;
  for (final t in monthTrips) {
    if (t.status != 'closed') continue;
    final k = t.km ?? 0;
    km += k;
    trips += 1;
    kmBy[t.project] = (kmBy[t.project] ?? 0) + k;
    countBy[t.project] = (countBy[t.project] ?? 0) + 1;
  }
  var within = 0;
  var excess = 0;
  var gauge = 0;
  if (s.scope == 'project') {
    for (final v in kmBy.values) {
      within += v > s.limitKm ? s.limitKm : v;
      excess += v > s.limitKm ? v - s.limitKm : 0;
      if (v > gauge) gauge = v;
    }
  } else {
    within = km > s.limitKm ? s.limitKm : km;
    excess = km > s.limitKm ? km - s.limitKm : 0;
    gauge = km;
  }
  return MonthSummary(
    trips: trips,
    km: km,
    within: within,
    excess: excess,
    amount: within * s.rate,
    gaugeKm: gauge,
    kmByProject: kmBy,
    tripsByProject: countBy,
  );
}

/// Short reasons a reviewer will look at twice.
List<String> tripFlags(Trip t, AppSettings s) {
  final out = <String>[];
  if (t.late != null) out.add('Late entry');
  if (t.meterReset != null) out.add('Meter reset');
  final prior = t.prior;
  if (prior != null && prior['none'] == true) out.add('No prior approval');
  if (t.start.oldPhoto || (t.end?.oldPhoto ?? false)) out.add('Photo not fresh');
  if ((t.km ?? 0) > s.highKm) out.add('High km');
  return out;
}
