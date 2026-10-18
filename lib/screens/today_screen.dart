import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/trip.dart';
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

  Future<void> _cancelTrip(BuildContext context, AppState state, Trip t) async {
    final reasonCtl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this trip?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The trip from ${t.from} stays in the log book as cancelled, with 0 km.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason *', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep trip')),
          FilledButton(
            onPressed: () {
              final r = reasonCtl.text.trim();
              if (r.isNotEmpty) Navigator.pop(ctx, r);
            },
            child: const Text('Cancel trip'),
          ),
        ],
      ),
    );
    if (reason != null) await state.cancelTrip(t, reason);
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
          value: limit > 0 ? (used / limit).clamp(0.0, 1.0).toDouble() : 0.0,
          minHeight: 12,
          borderRadius: BorderRadius.circular(6),
        ),
        const SizedBox(height: 8),
        Text('$used of $limit km · ₹${((used > limit ? limit : used) * rate).toStringAsFixed(0)} within limit'),
        const SizedBox(height: 24),
        if (open != null) ...[
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text('${open.from} → ${open.to}'),
                  subtitle: Text('${open.project} · ${open.vehicle} · started ${DateFormat.jm().format(DateTime.parse(open.start.at).toLocal())}'),
                  trailing: FilledButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripFormScreen(mode: 'end', trip: open))),
                    child: const Text('End trip'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _cancelTrip(context, state, open),
                    child: const Text('Cancel this trip'),
                  ),
                ),
              ],
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
