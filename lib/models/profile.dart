class Vehicle {
  final String no;
  final String type;

  Vehicle({required this.no, required this.type});

  Map<String, dynamic> toJson() => {'no': no, 'type': type};
  factory Vehicle.fromJson(Map<String, dynamic> j) =>
      Vehicle(no: j['no'] ?? '', type: j['type'] ?? '');
}

class Profile {
  String id;
  String name;
  String designation;
  String block;
  String district;
  String mobile;
  String role; // staff, bi, acc, di
  List<Vehicle> vehicles;
  String created;
  bool demo;

  Profile({
    required this.id,
    required this.name,
    this.designation = '',
    this.block = '',
    this.district = '',
    this.mobile = '',
    this.role = 'staff',
    this.vehicles = const [],
    required this.created,
    this.demo = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'designation': designation,
        'block': block,
        'district': district,
        'mobile': mobile,
        'role': role,
        'vehicles': vehicles.map((v) => v.toJson()).toList(),
        'created': created,
        'demo': demo,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        designation: j['designation'] ?? '',
        block: j['block'] ?? '',
        district: j['district'] ?? '',
        mobile: j['mobile'] ?? '',
        role: j['role'] ?? 'staff',
        vehicles: (j['vehicles'] as List? ?? [])
            .map((e) => Vehicle.fromJson(e as Map<String, dynamic>))
            .toList(),
        created: j['created'] ?? DateTime.now().toIso8601String(),
        demo: j['demo'] ?? false,
      );
}

class AppSettings {
  String org;
  String office;
  int limitKm;
  double rate;
  String scope; // staff | project
  int lateDays;
  int highKm;
  int photoMaxAge;
  List<String> projects;
  List<String> activities;
  List<String> places;

  AppSettings({
    this.org = 'Development Support Centre (DSC)',
    this.office = 'Nandurbar',
    this.limitKm = 500,
    this.rate = 4,
    this.scope = 'staff',
    this.lateDays = 3,
    this.highKm = 200,
    this.photoMaxAge = 30,
    this.projects = const [
      'ABF (Axis Bank Foundation)',
      'NABARD',
      'VCS 4285 Carbon',
      'Project SAHAS',
      'Lokkalyan CSR',
      'Office / General',
    ],
    this.activities = const [
      'Village meeting',
      'Training / workshop',
      'Survey / planning',
      'Work supervision',
      'Monitoring visit',
      'Govt. office / bank',
      'Office work',
      'Other',
    ],
    this.places = const [],
  });

  Map<String, dynamic> toJson() => {
        'org': org,
        'office': office,
        'limitKm': limitKm,
        'rate': rate,
        'scope': scope,
        'lateDays': lateDays,
        'highKm': highKm,
        'photoMaxAge': photoMaxAge,
        'projects': projects,
        'activities': activities,
        'places': places,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        org: j['org'] ?? 'Development Support Centre (DSC)',
        office: j['office'] ?? 'Nandurbar',
        limitKm: j['limitKm'] ?? 500,
        rate: (j['rate'] as num?)?.toDouble() ?? 4,
        scope: j['scope'] ?? 'staff',
        lateDays: j['lateDays'] ?? 3,
        highKm: j['highKm'] ?? 200,
        photoMaxAge: j['photoMaxAge'] ?? 30,
        projects: List<String>.from(j['projects'] ?? []),
        activities: List<String>.from(j['activities'] ?? []),
        places: List<String>.from(j['places'] ?? []),
      );
}
