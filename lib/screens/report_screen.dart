import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final trips = state.tripsOfMonth(month).where((t) => t.status == 'closed').toList();
    final claimed = trips.fold<int>(0, (s, t) => s + (t.km ?? 0));
    final rate = state.settings.rate;
    final limit = state.settings.limitKm;
    final within = claimed > limit ? limit : claimed;
    final excess = claimed > limit ? claimed - limit : 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Monthly report', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(month),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Trips: ${trips.length}'),
                Text('Km claimed: $claimed'),
                Text('Within limit: $within km'),
                Text('Above limit: $excess km'),
                const SizedBox(height: 8),
                Text('Payable so far: ₹${(within * rate).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Submit report (generates a self-contained HTML file that the original app can also open) — to be implemented with full photo embedding.'),
        const SizedBox(height: 8),
        FilledButton(onPressed: null, child: const Text('Submit to Block Integrator')),
      ],
    );
  }
}
