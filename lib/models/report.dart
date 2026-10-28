import 'profile.dart';
import 'trip.dart';

/// Version of the report file layout. A newer app can read older files.
const int reportFormat = 1;

/// File name ending of a report file passed around on WhatsApp or email.
const String reportFileExt = 'vlbreport';

/// The sign-off steps in order. 'submit' is the staff member's own.
const List<String> reportSteps = ['submit', 'bi', 'acc', 'di'];

/// Only letters, digits, dash and underscore. Used for ids and photo names that come from a file
/// and end up in file paths.
final RegExp safeName = RegExp(r'^[A-Za-z0-9_-]{1,80}$');

/// Thrown when a report file is damaged or a sign-off is not allowed.
class ReportError implements Exception {
  final String message;
  const ReportError(this.message);

  @override
  String toString() => message;
}

String _s(dynamic v) => v == null ? '' : '$v';

int _i(dynamic v) => v is num ? v.toInt() : (int.tryParse(_s(v)) ?? 0);

/// Who sent the report.
class ReportStaff {
  final String id;
  final String name;
  final String designation;
  final String block;
  final String district;
  final String mobile;

  const ReportStaff({
    required this.id,
    required this.name,
    this.designation = '',
    this.block = '',
    this.district = '',
    this.mobile = '',
  });

  factory ReportStaff.fromProfile(Profile p) => ReportStaff(
        id: p.id,
        name: p.name,
        designation: p.designation,
        block: p.block,
        district: p.district,
        mobile: p.mobile,
      );

  List<dynamic> get core => <dynamic>[id, name, designation, block, district, mobile];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'designation': designation,
        'block': block,
        'district': district,
        'mobile': mobile,
      };

  factory ReportStaff.fromJson(Map<String, dynamic> j) => ReportStaff(
        id: _s(j['id']),
        name: _s(j['name']),
        designation: _s(j['designation']),
        block: _s(j['block']),
        district: _s(j['district']),
        mobile: _s(j['mobile']),
      );
}

/// The office rules the figures in the report were worked out with.
class ReportPolicy {
  final String org;
  final String office;
  final int limitKm;
  final double rate;
  final String scope; // staff | project
  final int highKm;

  const ReportPolicy({
    required this.org,
    required this.office,
    required this.limitKm,
    required this.rate,
    required this.scope,
    required this.highKm,
  });

  factory ReportPolicy.fromSettings(AppSettings s) => ReportPolicy(
        org: s.org,
        office: s.office,
        limitKm: s.limitKm,
        rate: s.rate,
        scope: s.scope,
        highKm: s.highKm,
      );

  /// Settings that give the same totals and flags as when the report was sent.
  AppSettings toSettings() => AppSettings(
        org: org,
        office: office,
        limitKm: limitKm,
        rate: rate,
        scope: scope,
        highKm: highKm,
      );

  List<dynamic> get core => <dynamic>[org, office, limitKm, rate, scope, highKm];

  Map<String, dynamic> toJson() => {
        'org': org,
        'office': office,
        'limitKm': limitKm,
        'rate': rate,
        'scope': scope,
        'highKm': highKm,
      };

  factory ReportPolicy.fromJson(Map<String, dynamic> j) => ReportPolicy(
        org: _s(j['org']),
        office: _s(j['office']),
        limitKm: _i(j['limitKm']),
        rate: (j['rate'] as num?)?.toDouble() ?? 0.0,
        scope: _s(j['scope']).isEmpty ? 'staff' : _s(j['scope']),
        highKm: _i(j['highKm']),
      );
}

/// The month's totals as the staff member's phone worked them out.
class ReportSummary {
  final int trips;
  final int km;
  final int within;
  final int excess;
  final double amount;

  const ReportSummary({
    required this.trips,
    required this.km,
    required this.within,
    required this.excess,
    required this.amount,
  });

  List<dynamic> get core => <dynamic>[trips, km, within, excess, amount];

  Map<String, dynamic> toJson() => {
        'trips': trips,
        'km': km,
        'within': within,
        'excess': excess,
        'amount': amount,
      };

  factory ReportSummary.fromJson(Map<String, dynamic> j) => ReportSummary(
        trips: _i(j['trips']),
        km: _i(j['km']),
        within: _i(j['within']),
        excess: _i(j['excess']),
        amount: (j['amount'] as num?)?.toDouble() ?? 0.0,
      );
}

/// One signature on the report. Each carries the hash of the one before it, so none can be
/// removed, reordered or edited without the chain breaking.
class SignOff {
  /// submit | bi | acc | di
  final String step;
  final String userId;
  final String name;
  final String designation;

  /// staff | bi | acc | di
  final String role;
  final String at; // ISO
  /// sent | forward | return | approve
  final String decision;
  final String remarks;

  /// District Integrator only: also approve the km above the monthly limit.
  final bool excessApproved;
  final String prevHash;
  final String hash;

  const SignOff({
    required this.step,
    required this.userId,
    required this.name,
    this.designation = '',
    required this.role,
    required this.at,
    required this.decision,
    this.remarks = '',
    this.excessApproved = false,
    required this.prevHash,
    this.hash = '',
  });

  SignOff withHash(String h) => SignOff(
        step: step,
        userId: userId,
        name: name,
        designation: designation,
        role: role,
        at: at,
        decision: decision,
        remarks: remarks,
        excessApproved: excessApproved,
        prevHash: prevHash,
        hash: h,
      );

  bool get returned => decision == 'return';

  Map<String, dynamic> toJson() => {
        'step': step,
        'userId': userId,
        'name': name,
        'designation': designation,
        'role': role,
        'at': at,
        'decision': decision,
        'remarks': remarks,
        'excessApproved': excessApproved,
        'prevHash': prevHash,
        'hash': hash,
      };

  factory SignOff.fromJson(Map<String, dynamic> j) => SignOff(
        step: _s(j['step']),
        userId: _s(j['userId']),
        name: _s(j['name']),
        designation: _s(j['designation']),
        role: _s(j['role']),
        at: _s(j['at']),
        decision: _s(j['decision']),
        remarks: _s(j['remarks']),
        excessApproved: j['excessApproved'] == true,
        prevHash: _s(j['prevHash']),
        hash: _s(j['hash']),
      );
}

/// Why the earlier version of this report came back. Sent along with the next version.
class ReturnedNote {
  final int revision;
  final String step;
  final String name;
  final String role;
  final String remarks;
  final String at;

  /// The seal of the sign-off that returned it.
  final String hash;

  const ReturnedNote({
    required this.revision,
    required this.step,
    required this.name,
    required this.role,
    required this.remarks,
    required this.at,
    required this.hash,
  });

  factory ReturnedNote.of(int revision, SignOff s) => ReturnedNote(
        revision: revision,
        step: s.step,
        name: s.name,
        role: s.role,
        remarks: s.remarks,
        at: s.at,
        hash: s.hash,
      );

  List<dynamic> get core => <dynamic>[revision, step, name, role, remarks, at, hash];

  Map<String, dynamic> toJson() => {
        'revision': revision,
        'step': step,
        'name': name,
        'role': role,
        'remarks': remarks,
        'at': at,
        'hash': hash,
      };

  factory ReturnedNote.fromJson(Map<String, dynamic> j) => ReturnedNote(
        revision: _i(j['revision']),
        step: _s(j['step']),
        name: _s(j['name']),
        role: _s(j['role']),
        remarks: _s(j['remarks']),
        at: _s(j['at']),
        hash: _s(j['hash']),
      );
}

/// A month's log, sealed, with the sign-offs so far. This is what travels from phone to phone.
/// The odometer photos travel beside it in the file and are checked against [photoHashes].
class ReportPackage {
  final int format;
  final String reportId;
  final int revision;
  final String month; // YYYY-MM
  final ReportStaff staff;
  final ReportPolicy policy;
  final ReportSummary summary;
  final String submittedAt;
  final ReturnedNote? replaces;
  final List<Trip> trips;

  /// Photo name to SHA-256 of the picture.
  final Map<String, String> photoHashes;

  /// Fingerprint of everything above. The first sign-off is chained to it.
  final String contentHash;
  final List<SignOff> signoffs;

  const ReportPackage({
    this.format = reportFormat,
    required this.reportId,
    required this.revision,
    required this.month,
    required this.staff,
    required this.policy,
    required this.summary,
    required this.submittedAt,
    this.replaces,
    required this.trips,
    required this.photoHashes,
    required this.contentHash,
    required this.signoffs,
  });

  /// Folder and file name for this version of the report.
  String get key => '${reportId}_r$revision';

  ReportPackage withSignoff(SignOff s) => ReportPackage(
        format: format,
        reportId: reportId,
        revision: revision,
        month: month,
        staff: staff,
        policy: policy,
        summary: summary,
        submittedAt: submittedAt,
        replaces: replaces,
        trips: trips,
        photoHashes: photoHashes,
        contentHash: contentHash,
        signoffs: [...signoffs, s],
      );

  Map<String, dynamic> toJson() => {
        'format': format,
        'reportId': reportId,
        'revision': revision,
        'month': month,
        'staff': staff.toJson(),
        'policy': policy.toJson(),
        'summary': summary.toJson(),
        'submittedAt': submittedAt,
        'replaces': replaces?.toJson(),
        'trips': trips.map((t) => t.toJson()).toList(),
        'photoHashes': photoHashes,
        'contentHash': contentHash,
        'signoffs': signoffs.map((s) => s.toJson()).toList(),
      };

  /// Throws [ReportError] when the data is not a report.
  factory ReportPackage.fromJson(Map<String, dynamic> j) {
    try {
      final id = _s(j['reportId']);
      if (!safeName.hasMatch(id)) throw const ReportError('The report has a bad id.');
      final hashes = <String, String>{};
      final rawHashes = j['photoHashes'];
      if (rawHashes is Map) {
        for (final e in rawHashes.entries) {
          final k = _s(e.key);
          if (!safeName.hasMatch(k)) throw const ReportError('A photo in the report has a bad name.');
          hashes[k] = _s(e.value);
        }
      }
      return ReportPackage(
        format: _i(j['format']),
        reportId: id,
        revision: _i(j['revision']) < 1 ? 1 : _i(j['revision']),
        month: _s(j['month']),
        staff: ReportStaff.fromJson(Map<String, dynamic>.from(j['staff'] as Map)),
        policy: ReportPolicy.fromJson(Map<String, dynamic>.from(j['policy'] as Map)),
        summary: ReportSummary.fromJson(Map<String, dynamic>.from(j['summary'] as Map)),
        submittedAt: _s(j['submittedAt']),
        replaces: j['replaces'] == null ? null : ReturnedNote.fromJson(Map<String, dynamic>.from(j['replaces'] as Map)),
        trips: (j['trips'] as List).map((e) => Trip.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        photoHashes: hashes,
        contentHash: _s(j['contentHash']),
        signoffs: (j['signoffs'] as List).map((e) => SignOff.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
    } on ReportError {
      rethrow;
    } catch (_) {
      throw const ReportError('This file is not a vehicle log report, or it is damaged.');
    }
  }
}
