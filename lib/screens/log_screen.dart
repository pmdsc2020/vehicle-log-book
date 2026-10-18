import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/trip.dart';
import '../services/app_state.dart';
import '../services/trip_rules.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/trip_tiles.dart';
import '../ui/widgets.dart';

/// Every entry, month by month, newest day first.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  String? _month;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final settings = state.settings;

    final months = state.trips.map((t) => t.month).toSet().toList()..sort((a, b) => b.compareTo(a));
    final thisMonth = currentMonth();
    if (!months.contains(thisMonth)) months.insert(0, thisMonth);
    final month = (_month != null && months.contains(_month)) ? _month! : months.first;

    final list = state.tripsOfMonth(month)..sort((a, b) => tripOrder(b, a));
    final sum = summarise(list, settings);

    // Group by day, newest day first.
    final days = <String>[];
    final byDay = <String, List<Trip>>{};
    for (final t in list) {
      if (!byDay.containsKey(t.date)) {
        days.add(t.date);
        byDay[t.date] = <Trip>[];
      }
      byDay[t.date]!.add(t);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Text('Log book', style: tt.headlineSmall),
        const SizedBox(height: 14),
        MonthChips(
          months: months,
          selected: month,
          label: fmtMonthShort,
          onSelected: (m) => setState(() => _month = m),
        ),
        const SizedBox(height: 14),
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(child: StatCell(label: sum.trips == 1 ? 'trip' : 'trips', value: '${sum.trips}')),
              Expanded(child: StatCell(label: 'km', value: fmtKm(sum.km))),
              Expanded(child: StatCell(label: 'payable', value: fmtRs(sum.amount), color: cs.primary)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Surface(
              child: EmptyState(
                icon: Icons.menu_book_outlined,
                title: 'No entries in ${fmtMonthLong(month)}',
                body: 'Trips you log will appear here, locked, with the odometer photos.',
              ),
            ),
          )
        else
          for (final day in days) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text(fmtDay(day), style: tt.titleSmall)),
                  Text(
                    _dayKm(byDay[day]!),
                    style: numStyle(16, weight: FontWeight.w600, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            for (final t in byDay[day]!)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TripTile(
                  trip: t,
                  flags: tripFlags(t, settings),
                  onTap: () => showTripDetail(context, t.id),
                ),
              ),
          ],
      ],
    );
  }

  String _dayKm(List<Trip> trips) {
    var km = 0;
    for (final t in trips) {
      if (t.status == 'closed') km += t.km ?? 0;
    }
    return '${fmtKm(km)} km';
  }
}
