import 'package:intl/intl.dart';

/// "Sun, 18 Oct" from yyyy-MM-dd.
String fmtDay(String ymd) {
  try {
    return DateFormat('EEE, d MMM').format(DateTime.parse(ymd));
  } catch (_) {
    return ymd;
  }
}

/// "9:40 am" from a UTC ISO time, shown in local time.
String fmtTime(String iso) {
  try {
    return DateFormat('h:mm a').format(DateTime.parse(iso).toLocal()).toLowerCase();
  } catch (_) {
    return iso;
  }
}

/// "18 Oct 2026, 9:40 am".
String fmtDateTime(String iso) {
  try {
    final d = DateTime.parse(iso).toLocal();
    return '${DateFormat('d MMM yyyy').format(d)}, ${DateFormat('h:mm a').format(d).toLowerCase()}';
  } catch (_) {
    return iso;
  }
}

/// "October 2026" from yyyy-MM.
String fmtMonthLong(String ym) {
  try {
    return DateFormat('MMMM yyyy').format(DateTime.parse('$ym-01'));
  } catch (_) {
    return ym;
  }
}

/// "Oct 2026" from yyyy-MM.
String fmtMonthShort(String ym) {
  try {
    return DateFormat('MMM yyyy').format(DateTime.parse('$ym-01'));
  } catch (_) {
    return ym;
  }
}

/// "2 h 10 min", "35 min", "just now".
String fmtElapsed(Duration d) {
  final m = d.inMinutes;
  if (m < 1) return 'just now';
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}

/// Two initials from a name, for the avatar.
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

String currentMonth() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}';
}

String roleLabel(String role) {
  switch (role) {
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

/// "Sunday, 18 October".
String fmtToday(DateTime d) => DateFormat('EEEE, d MMMM').format(d);

String greetingFor(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// "18 Oct 2026" from yyyy-MM-dd.
String fmtDayYear(String ymd) {
  try {
    return DateFormat('EEE, d MMM yyyy').format(DateTime.parse(ymd));
  } catch (_) {
    return ymd;
  }
}
