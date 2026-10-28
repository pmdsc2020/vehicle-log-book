import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/profile.dart';
import '../models/report.dart';
import '../models/trip.dart';
import 'trip_rules.dart';

/// Building, signing, packing and checking a month's report. No screens, no storage.
///
/// How it works without a server: the report is one file. It holds the month's sealed trips, the
/// odometer photos and a chain of sign-offs. Each person opens the file in the app, checks it,
/// signs, and passes the file on. Every sign-off carries the hash of what came before it, so a
/// change made anywhere along the way shows up when the next person (or the staff member) opens it.

// ---------------------------------------------------------------- names and labels

/// The step a profile role signs, or null for field staff.
String? stepOfRole(String role) => (role == 'bi' || role == 'acc' || role == 'di') ? role : null;

String stepRoleLabel(String step) {
  switch (step) {
    case 'bi':
      return 'Block Integrator';
    case 'acc':
      return 'Accountant';
    case 'di':
      return 'District Integrator';
    default:
      return 'Field staff';
  }
}

/// What the person did, as a past-tense verb: Checked, Verified, Approved, Returned, Sent.
String signoffVerb(SignOff s) {
  if (s.returned) return 'Returned';
  switch (s.step) {
    case 'bi':
      return 'Checked';
    case 'acc':
      return 'Verified';
    case 'di':
      return 'Approved';
    default:
      return 'Sent';
  }
}

/// Decisions allowed at each step.
List<String> decisionsFor(String step) {
  switch (step) {
    case 'bi':
    case 'acc':
      return const ['forward', 'return'];
    case 'di':
      return const ['approve', 'return'];
    default:
      return const ['sent'];
  }
}

// ---------------------------------------------------------------- hashes

/// Fingerprint of everything the staff member sent: the trips (all fields, notes included), the
/// figures, the rules and the photo fingerprints.
String reportContentHash(ReportPackage p) {
  final keys = p.photoHashes.keys.toList()..sort();
  final core = <dynamic>[
    'vlb-report',
    p.format,
    p.reportId,
    p.revision,
    p.month,
    p.staff.core,
    p.policy.core,
    p.summary.core,
    p.submittedAt,
    p.replaces?.core ?? '',
    [for (final t in p.trips) sha256Hex(jsonEncode(t.toJson()))],
    [
      for (final k in keys) [k, p.photoHashes[k]],
    ],
  ];
  return sha256Hex(jsonEncode(core));
}

String signoffHash(ReportPackage p, SignOff s) => sha256Hex(jsonEncode(<dynamic>[
      'vlb-signoff',
      p.reportId,
      p.revision,
      s.step,
      s.userId,
      s.name,
      s.designation,
      s.role,
      s.at,
      s.decision,
      s.remarks,
      s.excessApproved,
      s.prevHash,
    ]));

String hashBytes(List<int> bytes) => sha256.convert(bytes).toString();

Map<String, String> hashPhotos(Map<String, List<int>> photos) => {
      for (final e in photos.entries) e.key: hashBytes(e.value),
    };

/// Photo names used by a trip's readings.
List<String> photoKeysOf(Trip t) => [
      if ((t.start.photoKey ?? '').isNotEmpty) t.start.photoKey!,
      if ((t.end?.photoKey ?? '').isNotEmpty) t.end!.photoKey!,
    ];

// ---------------------------------------------------------------- building

/// Why a month cannot be sent yet, or null when it can.
String? reportBlocker(List<Trip> monthTrips) {
  if (monthTrips.any((t) => t.status == 'open')) {
    return 'A trip is still open. End it or cancel it first.';
  }
  if (!monthTrips.any((t) => t.status == 'closed')) {
    return 'There are no finished trips this month.';
  }
  return null;
}

/// Seals a month's trips into a report and signs it as sent. [photos] must hold every picture the
/// trips point to.
ReportPackage buildReport({
  required Profile staff,
  required AppSettings settings,
  required String month,
  required List<Trip> trips,
  required Map<String, List<int>> photos,
  int revision = 1,
  ReturnedNote? replaces,
  String? reportId,
  String? at,
}) {
  // A copy, so notes added later to the live trips do not change what was sent.
  final sorted = [
    for (final t in trips) Trip.fromJson(Map<String, dynamic>.from(jsonDecode(jsonEncode(t.toJson())) as Map)),
  ]..sort(tripOrder);
  final when = at ?? nowIso();
  final sum = summarise(sorted, settings);
  final base = ReportPackage(
    reportId: reportId ?? 'R$month-${_idPart(staff.id)}',
    revision: revision,
    month: month,
    staff: ReportStaff.fromProfile(staff),
    policy: ReportPolicy.fromSettings(settings),
    summary: ReportSummary(trips: sum.trips, km: sum.km, within: sum.within, excess: sum.excess, amount: sum.amount),
    submittedAt: when,
    replaces: replaces,
    trips: sorted,
    photoHashes: hashPhotos(photos),
    contentHash: '',
    signoffs: const [],
  );
  final content = reportContentHash(base);
  final sealed = ReportPackage(
    reportId: base.reportId,
    revision: base.revision,
    month: base.month,
    staff: base.staff,
    policy: base.policy,
    summary: base.summary,
    submittedAt: base.submittedAt,
    replaces: base.replaces,
    trips: base.trips,
    photoHashes: base.photoHashes,
    contentHash: content,
    signoffs: const [],
  );
  final first = SignOff(
    step: 'submit',
    userId: staff.id,
    name: staff.name,
    designation: staff.designation,
    role: 'staff',
    at: when,
    decision: 'sent',
    prevHash: content,
  );
  return sealed.withSignoff(first.withHash(signoffHash(sealed, first)));
}

/// The month before or after [month] (YYYY-MM).
String shiftMonth(String month, int by) {
  final y = int.tryParse(month.substring(0, 4)) ?? 2000;
  final m = int.tryParse(month.substring(5, 7)) ?? 1;
  final d = DateTime(y, m + by, 1);
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
}

String _idPart(String id) {
  final s = id.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
  return s.isEmpty ? 'staff' : (s.length > 24 ? s.substring(0, 24) : s);
}

// ---------------------------------------------------------------- where the report stands

enum ReportStage { withBi, withAcc, withDi, approved, returned }

class ReportStatus {
  final ReportStage stage;

  /// How many of the four steps (staff, BI, Accountant, DI) are finished.
  final int done;

  /// Index of the step that sent it back, when returned.
  final int? returnedAt;
  final SignOff? last;

  const ReportStatus(this.stage, this.done, this.returnedAt, this.last);

  /// The step that signs next, or null when the report has finished.
  String? get nextStep {
    switch (stage) {
      case ReportStage.withBi:
        return 'bi';
      case ReportStage.withAcc:
        return 'acc';
      case ReportStage.withDi:
        return 'di';
      default:
        return null;
    }
  }

  bool get finished => stage == ReportStage.approved || stage == ReportStage.returned;
}

ReportStatus statusOf(ReportPackage p) {
  if (p.signoffs.isEmpty) return const ReportStatus(ReportStage.withBi, 0, null, null);
  final last = p.signoffs.last;
  final idx = reportSteps.indexOf(last.step);
  if (last.returned) return ReportStatus(ReportStage.returned, idx < 0 ? 0 : idx, idx < 0 ? 0 : idx, last);
  switch (last.step) {
    case 'submit':
      return ReportStatus(ReportStage.withBi, 1, null, last);
    case 'bi':
      return ReportStatus(ReportStage.withAcc, 2, null, last);
    case 'acc':
      return ReportStatus(ReportStage.withDi, 3, null, last);
    case 'di':
      return ReportStatus(ReportStage.approved, 4, null, last);
  }
  return ReportStatus(ReportStage.withBi, 0, null, last);
}

String stageLabel(ReportStatus s) {
  switch (s.stage) {
    case ReportStage.withBi:
      return 'With Block Integrator';
    case ReportStage.withAcc:
      return 'With Accountant';
    case ReportStage.withDi:
      return 'With District Integrator';
    case ReportStage.approved:
      return 'Approved';
    case ReportStage.returned:
      return 'Returned';
  }
}

/// The District Integrator's decision on the km above the limit, once approved.
SignOff? approvalOf(ReportPackage p) {
  for (final s in p.signoffs) {
    if (s.step == 'di' && s.decision == 'approve') return s;
  }
  return null;
}

/// Km that will be paid: those inside the limit, plus the km above it if the District Integrator
/// approved them.
int payableKm(ReportPackage p) {
  final a = approvalOf(p);
  return p.summary.within + ((a != null && a.excessApproved) ? p.summary.excess : 0);
}

double payableAmount(ReportPackage p) => payableKm(p) * p.policy.rate;

// ---------------------------------------------------------------- signing

/// Adds [by]'s sign-off to the report. Throws [ReportError] when it is not their turn.
ReportPackage signReport(
  ReportPackage p,
  Profile by, {
  required String decision,
  String remarks = '',
  bool excessApproved = false,
  String? at,
}) {
  final st = statusOf(p);
  final step = st.nextStep;
  if (step == null) {
    throw const ReportError('This report has already finished. Nothing more can be signed on it.');
  }
  if (by.id == p.staff.id) throw const ReportError('You cannot sign off your own report.');
  if (stepOfRole(by.role) != step) {
    throw ReportError('This report is waiting for the ${stepRoleLabel(step)}. You are signed in as ${stepRoleLabel(by.role)}.');
  }
  if (!decisionsFor(step).contains(decision)) throw const ReportError('That is not a choice at this step.');
  final note = remarks.trim();
  if (decision == 'return' && note.isEmpty) throw const ReportError('Write why you are sending it back.');
  final s = SignOff(
    step: step,
    userId: by.id,
    name: by.name,
    designation: by.designation,
    role: by.role,
    at: at ?? nowIso(),
    decision: decision,
    remarks: note,
    excessApproved: step == 'di' && decision == 'approve' && p.summary.excess > 0 && excessApproved,
    prevHash: p.signoffs.last.hash,
  );
  return p.withSignoff(s.withHash(signoffHash(p, s)));
}

// ---------------------------------------------------------------- checking

enum CheckState { ok, warn, bad }

class CheckLine {
  final CheckState state;
  final String title;
  final String detail;
  const CheckLine(this.state, this.title, [this.detail = '']);
}

class PackageCheck {
  final List<CheckLine> lines;
  const PackageCheck(this.lines);

  bool get ok => !lines.any((l) => l.state == CheckState.bad);
  bool get hasWarnings => lines.any((l) => l.state == CheckState.warn);
  List<CheckLine> get problems => lines.where((l) => l.state == CheckState.bad).toList();
}

String _tripName(Trip t) => '${fmtDate(t.date)} to ${t.to}';

String _someOf(List<String> items) {
  if (items.length <= 3) return items.join('; ');
  return '${items.take(3).join('; ')}; and ${items.length - 3} more';
}

/// Checks a report the way every person who opens it does. [actualPhotos] holds the SHA-256 of
/// each picture really present (from the file or from the phone). [previous] is the same person's
/// report for the month before, if this phone holds it.
PackageCheck verifyReport(ReportPackage p, Map<String, String> actualPhotos, {ReportPackage? previous}) {
  final lines = <CheckLine>[];

  // 1. The file is a whole report.
  final structure = <String>[];
  if (p.format < 1 || p.format > reportFormat) structure.add('It was made by a newer version of the app.');
  if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(p.month)) structure.add('The month is not valid.');
  if (p.staff.id.isEmpty || p.staff.name.isEmpty) structure.add('It does not say who sent it.');
  if (p.trips.isEmpty) structure.add('It has no trips.');
  if (p.signoffs.isEmpty || p.signoffs.first.step != 'submit') structure.add('It was never sent by the staff member.');
  if (structure.isNotEmpty) {
    lines.add(CheckLine(CheckState.bad, 'The report is incomplete', structure.join(' ')));
    return PackageCheck(lines);
  }

  // 2. Nothing changed since it was sent.
  if (reportContentHash(p) == p.contentHash) {
    lines.add(const CheckLine(CheckState.ok, 'Report fingerprint matches', 'Nothing changed after the staff member sent it.'));
  } else {
    lines.add(const CheckLine(
        CheckState.bad, 'Report fingerprint does not match', 'Something in the trips, figures or photos changed after it was sent.'));
  }

  // 3. Every trip still matches its seal.
  final badSeals = <String>[];
  final wrongMonth = <String>[];
  final stillOpen = <String>[];
  for (final t in p.trips) {
    if (t.status == 'open') {
      stillOpen.add(_tripName(t));
    } else if (!sealIntact(t)) {
      badSeals.add(_tripName(t));
    }
    if (t.month != p.month) wrongMonth.add(_tripName(t));
  }
  if (stillOpen.isNotEmpty) {
    lines.add(CheckLine(CheckState.bad, 'A trip is still open', _someOf(stillOpen)));
  } else if (badSeals.isNotEmpty) {
    lines.add(CheckLine(CheckState.bad, '${badSeals.length} of ${p.trips.length} trips do not match their seal', _someOf(badSeals)));
  } else {
    final cancelled = p.trips.where((t) => t.status == 'cancelled').length;
    lines.add(CheckLine(
      CheckState.ok,
      'All ${p.trips.length} entries match their seals',
      cancelled > 0
          ? '${p.trips.length - cancelled} trips and $cancelled cancelled. None was edited after it was locked.'
          : 'None was edited after it was locked.',
    ));
  }
  if (wrongMonth.isNotEmpty) {
    lines.add(CheckLine(CheckState.bad, 'Trips from another month are in this report', _someOf(wrongMonth)));
  }

  // 4. The trips are linked one to the next.
  final byPos = p.trips.where((t) => t.chainPos != null).toList()..sort((a, b) => a.chainPos!.compareTo(b.chainPos!));
  final unsealed = p.trips.length - byPos.length;
  final broken = <String>[];
  final gaps = <String>[];
  var dup = false;
  for (var i = 1; i < byPos.length; i++) {
    final a = byPos[i - 1];
    final b = byPos[i];
    if (a.chainPos == b.chainPos) {
      dup = true;
    } else if (b.chainPos! == a.chainPos! + 1) {
      if (b.prevHash != a.hash) broken.add('${_tripName(a)} and ${_tripName(b)}');
    } else {
      gaps.add('${a.chainPos! + 1}-${b.chainPos! - 1}');
    }
  }
  if (unsealed > 0 || dup || broken.isNotEmpty) {
    lines.add(CheckLine(
      CheckState.bad,
      'The chain of trips is broken',
      [
        if (unsealed > 0) '$unsealed trips were never locked.',
        if (dup) 'Two trips share one place in the chain.',
        if (broken.isNotEmpty) 'Not linked: ${_someOf(broken)}.',
      ].join(' '),
    ));
  } else if (gaps.isNotEmpty) {
    lines.add(CheckLine(
      CheckState.warn,
      'Entries ${_someOf(gaps)} are not in this report',
      'They belong to another month, which is normal when a late entry crosses a month end. '
          'If that is not the case, ask for the full log.',
    ));
  } else {
    lines.add(const CheckLine(CheckState.ok, 'Trips are linked in order', 'No entry is missing from the chain.'));
  }

  // 5. Odometer photos.
  var readings = 0;
  var missing = 0;
  var altered = 0;
  for (final t in p.trips) {
    for (final r in [t.start, if (t.end != null) t.end!]) {
      readings += 1;
      final key = r.photoKey ?? '';
      final want = r.photoHash ?? '';
      final listed = p.photoHashes[key];
      final actual = actualPhotos[key];
      if (key.isEmpty || want.isEmpty || listed == null || actual == null) {
        missing += 1;
      } else if (actual != want || listed != want) {
        altered += 1;
      }
    }
  }
  if (missing > 0 || altered > 0) {
    lines.add(CheckLine(
      CheckState.bad,
      'Odometer photos: ${missing + altered} of $readings cannot be trusted',
      [
        if (missing > 0) '$missing missing.',
        if (altered > 0) '$altered do not match the fingerprint taken when the trip was locked.',
      ].join(' '),
    ));
  } else {
    lines.add(CheckLine(CheckState.ok, 'All $readings odometer photos are present and unchanged'));
  }

  // 6. The figures follow from the trips.
  final again = summarise(p.trips, p.policy.toSettings());
  final s = p.summary;
  if (again.trips == s.trips && again.km == s.km && again.within == s.within && again.excess == s.excess && again.amount == s.amount) {
    lines.add(const CheckLine(CheckState.ok, 'Figures match the trips', 'Km and amount were worked out again from the trips.'));
  } else {
    lines.add(const CheckLine(CheckState.bad, 'Figures do not match the trips', 'The km or amount in the statement differ from the trips.'));
  }

  // 7. Sign-offs.
  final signProblems = <String>[];
  var expectPrev = p.contentHash;
  for (var i = 0; i < p.signoffs.length; i++) {
    final so = p.signoffs[i];
    final who = '${signoffVerb(so)} by ${so.name}';
    if (i >= reportSteps.length || so.step != reportSteps[i]) {
      signProblems.add('$who is out of order.');
      break;
    }
    if (so.prevHash != expectPrev) signProblems.add('$who does not follow the one before it.');
    if (signoffHash(p, so) != so.hash) signProblems.add('$who was changed.');
    if (i == 0 && so.userId != p.staff.id) signProblems.add('The first sign-off is not by the staff member.');
    if (i > 0 && so.userId == p.staff.id) signProblems.add('$who signed their own report.');
    if (!decisionsFor(so.step).contains(so.decision)) signProblems.add('$who has an invalid decision.');
    if (i < p.signoffs.length - 1 && (so.returned || so.decision == 'approve')) {
      signProblems.add('Someone signed after the report was finished.');
    }
    expectPrev = so.hash;
  }
  if (signProblems.isNotEmpty) {
    lines.add(CheckLine(CheckState.bad, 'Sign-offs do not add up', _someOf(signProblems)));
  } else {
    final n = p.signoffs.length;
    lines.add(CheckLine(CheckState.ok, n == 1 ? 'Sent by ${p.staff.name}' : '$n sign-offs, in order and unchanged'));
  }

  // 8. Continues from the month before.
  if (previous != null && byPos.isNotEmpty) {
    final earlier = previous.trips.where((t) => t.chainPos != null).toList()..sort((a, b) => a.chainPos!.compareTo(b.chainPos!));
    if (earlier.isNotEmpty) {
      final last = earlier.last;
      final first = byPos.first;
      if (first.chainPos == last.chainPos! + 1 && first.prevHash == last.hash) {
        lines.add(const CheckLine(CheckState.ok, 'Continues from the earlier month', 'The first trip follows the last one in the earlier report.'));
      } else {
        lines.add(const CheckLine(
          CheckState.warn,
          'Does not continue from the earlier month',
          'Some entries between the two reports may be missing, or the staff member changed phone.',
        ));
      }
    }
  }

  return PackageCheck(lines);
}

// ---------------------------------------------------------------- the file

/// What travels: the report and its photos.
class ReportFile {
  final ReportPackage report;
  final Map<String, Uint8List> photos;
  const ReportFile(this.report, this.photos);
}

const int _maxFileBytes = 120 * 1024 * 1024;
const int _maxPhotos = 600;

/// Packs the report and photos into one compressed file.
Uint8List encodeReportFile(ReportPackage p, Map<String, List<int>> photos) {
  final json = <String, dynamic>{
    ...p.toJson(),
    'photos': {for (final e in photos.entries) e.key: base64Encode(e.value)},
  };
  return Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(json))));
}

/// Opens a report file. Throws [ReportError] when it is not one, or is damaged.
ReportFile decodeReportFile(List<int> bytes) {
  if (bytes.isEmpty) throw const ReportError('The file is empty.');
  if (bytes.length > _maxFileBytes) throw const ReportError('The file is too large to be a report.');
  try {
    final raw = (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) ? gzip.decode(bytes) : bytes;
    final decoded = jsonDecode(utf8.decode(raw));
    if (decoded is! Map) throw const ReportError('This file is not a vehicle log report.');
    final json = Map<String, dynamic>.from(decoded);
    final report = ReportPackage.fromJson(json);
    final photos = <String, Uint8List>{};
    final rawPhotos = json['photos'];
    if (rawPhotos is Map) {
      if (rawPhotos.length > _maxPhotos) throw const ReportError('The file has too many photos.');
      for (final e in rawPhotos.entries) {
        final k = '${e.key}';
        if (!safeName.hasMatch(k)) throw const ReportError('A photo in the file has a bad name.');
        photos[k] = base64Decode('${e.value}');
      }
    }
    return ReportFile(report, photos);
  } on ReportError {
    rethrow;
  } catch (_) {
    throw const ReportError('This file is not a vehicle log report, or it is damaged.');
  }
}

/// A readable file name for a report, for the share sheet.
String reportFileName(ReportPackage p) {
  final who = p.staff.name.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  final stage = p.signoffs.length;
  return 'VehicleLog_${p.month}_${who.isEmpty ? 'staff' : who}_r${p.revision}_s$stage.$reportFileExt';
}
