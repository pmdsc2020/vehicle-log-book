class GpsPoint {
  final double lat;
  final double lng;
  final int acc;

  GpsPoint({required this.lat, required this.lng, this.acc = 0});

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'acc': acc};
  factory GpsPoint.fromJson(Map<String, dynamic>? j) => j == null
      ? GpsPoint(lat: 0, lng: 0)
      : GpsPoint(lat: (j['lat'] as num).toDouble(), lng: (j['lng'] as num).toDouble(), acc: j['acc'] ?? 0);
}

class Reading {
  final int km;
  final String? photoKey;
  final String? photoHash;
  final String at; // ISO
  final GpsPoint? gps;
  final String? photoTime;
  final bool oldPhoto;
  final int? prevKm;
  final String? returnTo;
  final String? remarks;

  Reading({
    required this.km,
    this.photoKey,
    this.photoHash,
    required this.at,
    this.gps,
    this.photoTime,
    this.oldPhoto = false,
    this.prevKm,
    this.returnTo,
    this.remarks,
  });

  Map<String, dynamic> toJson() => {
        'km': km,
        'photo': photoKey,
        'photoHash': photoHash,
        'at': at,
        'gps': gps?.toJson(),
        'photoTime': photoTime,
        'oldPhoto': oldPhoto,
        'prevKm': prevKm,
        'returnTo': returnTo,
        'remarks': remarks,
      };

  factory Reading.fromJson(Map<String, dynamic> j) => Reading(
        km: j['km'] ?? 0,
        photoKey: j['photo'],
        photoHash: j['photoHash'],
        at: j['at'] ?? '',
        gps: j['gps'] != null ? GpsPoint.fromJson(j['gps']) : null,
        photoTime: j['photoTime'],
        oldPhoto: j['oldPhoto'] ?? false,
        prevKm: j['prevKm'],
        returnTo: j['returnTo'],
        remarks: j['remarks'],
      );
}

class Note {
  final String at;
  final String text;
  Note({required this.at, required this.text});
  Map<String, dynamic> toJson() => {'at': at, 'text': text};
  factory Note.fromJson(Map<String, dynamic> j) => Note(at: j['at'] ?? '', text: j['text'] ?? '');
}

class Trip {
  final String id;
  final int schema;
  final String mode; // start | full
  final String date; // YYYY-MM-DD
  final String month; // YYYY-MM
  final String project;
  final String vehicle;
  final String vtype;
  final String from;
  final String to;
  final String activity;
  final String task;
  final Reading start;
  Reading? end;
  int? km;
  String status; // open | closed | cancelled
  final Map<String, dynamic>? late;
  final Map<String, dynamic>? meterReset;
  final Map<String, dynamic>? prior;
  Map<String, dynamic>? cancel;
  List<Note> notes;
  final String loggedAt;
  int? chainPos;
  String? prevHash;
  String? lockedAt;
  String? hash;

  Trip({
    required this.id,
    this.schema = 1,
    required this.mode,
    required this.date,
    required this.month,
    required this.project,
    required this.vehicle,
    this.vtype = '',
    required this.from,
    required this.to,
    required this.activity,
    required this.task,
    required this.start,
    this.end,
    this.km,
    this.status = 'open',
    this.late,
    this.meterReset,
    this.prior,
    this.cancel,
    this.notes = const [],
    required this.loggedAt,
    this.chainPos,
    this.prevHash,
    this.lockedAt,
    this.hash,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'schema': schema,
        'mode': mode,
        'date': date,
        'month': month,
        'project': project,
        'vehicle': vehicle,
        'vtype': vtype,
        'from': from,
        'to': to,
        'activity': activity,
        'task': task,
        'start': start.toJson(),
        'end': end?.toJson(),
        'km': km,
        'status': status,
        'late': late,
        'meterReset': meterReset,
        'prior': prior,
        'cancel': cancel,
        'notes': notes.map((n) => n.toJson()).toList(),
        'loggedAt': loggedAt,
        'chainPos': chainPos,
        'prevHash': prevHash,
        'lockedAt': lockedAt,
        'hash': hash,
      };

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] ?? '',
        schema: j['schema'] ?? 1,
        mode: j['mode'] ?? 'start',
        date: j['date'] ?? '',
        month: j['month'] ?? '',
        project: j['project'] ?? '',
        vehicle: j['vehicle'] ?? '',
        vtype: j['vtype'] ?? '',
        from: j['from'] ?? '',
        to: j['to'] ?? '',
        activity: j['activity'] ?? '',
        task: j['task'] ?? '',
        start: Reading.fromJson(j['start'] ?? {}),
        end: j['end'] != null ? Reading.fromJson(j['end']) : null,
        km: j['km'],
        status: j['status'] ?? 'open',
        late: j['late'],
        meterReset: j['meterReset'],
        prior: j['prior'],
        cancel: j['cancel'],
        notes: (j['notes'] as List? ?? []).map((e) => Note.fromJson(e)).toList(),
        loggedAt: j['loggedAt'] ?? '',
        chainPos: j['chainPos'],
        prevHash: j['prevHash'],
        lockedAt: j['lockedAt'],
        hash: j['hash'],
      );
}
