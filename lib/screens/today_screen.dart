import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'trip_form_screen.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  String _fmtMonth(String m) {
    final parts = m.split('-');
    if (parts.length != 2) return m;
    final months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return '${months[int.parse(parts[1]) - 1]} ${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final open = state.openTrip();
    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final monthTrips = state.tripsOfMonth(month).where((t) => t.status == 'closed').toList();
    final used = monthTrips.fold<int>(0, (s, t) => s + (t.km ?? 0));
    final limit = state.settings.limitKm;
    final rate = state.settings.rate;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(_fmtMonth(month), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Text('Vehicle use this month', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: limit > 0 ? (used / limit).clamp(0, 1) : 0,
          minHeight: 12,
          borderRadius: BorderRadius.circular(6),
        ),
        const SizedBox(height: 8),
        Text('$used of $limit km · ₹${(used * rate).toStringAsFixed(0)} within limit'),
        const SizedBox(height: 24),
        if (open != null) ...[
          Card(
            child: ListTile(
              title: Text('${open.from} → ${open.to}'),
              subtitle: Text('${open.project} · started ${DateFormat.jm().format(DateTime.parse(open.start.at))}'),
              trailing: FilledButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripFormScreen(mode: 'end', trip: open))),
                child: const Text('End trip'),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: open == null
              ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TripFormScreen(mode: 'start')))
              : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start a trip'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TripFormScreen(mode: 'full'))),
          icon: const Icon(Icons.add),
          label: const Text('Log a finished trip'),
        ),
      ],
    );
  }
}
