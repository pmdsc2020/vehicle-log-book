import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/trip_rules.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/trip_tiles.dart';
import '../ui/widgets.dart';

/// The month as a statement: what was travelled, what is payable, who signs it off.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
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

    final trips = state.tripsOfMonth(month);
    final sum = summarise(trips, settings);
    final flagged = trips.where((t) => t.status != 'cancelled' && tripFlags(t, settings).isNotEmpty).toList();
    final project = settings.scope == 'project';

    final projects = sum.kmByProject.keys.toList()
      ..sort((a, b) => (sum.kmByProject[b] ?? 0).compareTo(sum.kmByProject[a] ?? 0));
    final maxKm = projects.isEmpty ? 1 : (sum.kmByProject[projects.first] ?? 1);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Text('Monthly report', style: tt.headlineSmall),
        const SizedBox(height: 14),
        MonthChips(
          months: months,
          selected: month,
          label: fmtMonthShort,
          onSelected: (m) => setState(() => _month = m),
        ),
        const SizedBox(height: 14),
        Surface(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(fmtMonthLong(month), style: tt.titleMedium),
              const SizedBox(height: 2),
              Text(
                state.profile!.name,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              LedgerRow(label: 'Trips', value: '${sum.trips}'),
              LedgerRow(label: 'Km travelled', value: fmtKm(sum.km)),
              LedgerRow(
                label: 'Within ${fmtKm(settings.limitKm)} km${project ? ' per project' : ''}',
                value: '${fmtKm(sum.within)} km',
              ),
              LedgerRow(
                label: 'Above the limit',
                value: '${fmtKm(sum.excess)} km',
                valueColor: sum.excess > 0 ? cs.tertiary : null,
              ),
              const SizedBox(height: 4),
              Divider(color: cs.outlineVariant),
              const SizedBox(height: 4),
              LedgerRow(label: 'Payable', value: fmtRs(sum.amount), strong: true, valueColor: cs.primary),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${fmtKm(sum.within)} km at ₹${_rate(settings.rate)} a km.'
                  '${sum.excess > 0 ? ' Km above the limit are paid only after District Integrator approval.' : ''}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        if (projects.isNotEmpty) ...[
          const SizedBox(height: 8),
          const SectionTitle('By project'),
          Surface(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              children: [
                for (final p in projects)
                  _ProjectBar(
                    name: p,
                    km: sum.kmByProject[p] ?? 0,
                    trips: sum.tripsByProject[p] ?? 0,
                    fraction: (sum.kmByProject[p] ?? 0) / maxKm,
                  ),
              ],
            ),
          ),
        ],
        if (flagged.isNotEmpty) ...[
          const SizedBox(height: 8),
          SectionTitle('Worth a second look', trailing: StatusPill('${flagged.length}', kind: PillKind.flag)),
          for (final t in flagged)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TripTile(
                trip: t,
                showDate: true,
                flags: tripFlags(t, settings),
                onTap: () => showTripDetail(context, t.id),
              ),
            ),
        ],
        const SizedBox(height: 8),
        const SectionTitle('Sign-off'),
        Surface(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ApprovalChain(done: 0),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'Your report goes to the Block Integrator first, then the Accountant, then the District Integrator.',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const FilledButton(onPressed: null, child: Text('Send to Block Integrator')),
        const SizedBox(height: 8),
        Text(
          'Sending the report is not in this version of the app yet. Your trips are saved and will be included when it is.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _rate(double r) => r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(2);
}

class _ProjectBar extends StatelessWidget {
  final String name;
  final int km;
  final int trips;
  final double fraction;

  const _ProjectBar({required this.name, required this.km, required this.trips, required this.fraction});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text(name, style: tt.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 12),
              Text('${fmtKm(km)} km', style: numStyle(18, weight: FontWeight.w600, color: cs.onSurface)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
              backgroundColor: cs.surfaceContainerHigh,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(trips == 1 ? '1 trip' : '$trips trips', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
