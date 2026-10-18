import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../models/trip.dart';
import '../services/app_state.dart';
import '../services/trip_rules.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/trip_tiles.dart';
import '../ui/widgets.dart';
import 'trip_form_screen.dart';

class TodayScreen extends StatelessWidget {
  /// Switches to the Log book tab.
  final VoidCallback? onSeeAll;

  const TodayScreen({super.key, this.onSeeAll});

  Future<void> _cancelTrip(BuildContext context, AppState state, Trip t) async {
    final ctl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this trip?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The trip to ${t.to} stays in the log book as cancelled, with 0 km.'),
            const SizedBox(height: 14),
            TextField(
              controller: ctl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep trip')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () {
              final r = ctl.text.trim();
              if (r.isNotEmpty) Navigator.pop(ctx, r);
            },
            child: const Text('Cancel trip'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (reason != null) await state.cancelTrip(t, reason);
  }

  void _open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final settings = state.settings;
    final open = state.openTrip();
    final month = currentMonth();
    final sum = summarise(state.tripsOfMonth(month), settings);
    final recent = state.recentTrips(4);
    final now = DateTime.now();
    final first = state.profile!.name.trim().split(RegExp(r'\s+')).first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Text('${greetingFor(now.hour)}, $first', style: tt.headlineSmall),
        const SizedBox(height: 4),
        Text(fmtToday(now), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 16),
        _MonthHero(month: month, sum: sum, settings: settings),
        const SizedBox(height: 16),
        if (open != null) ...[
          _OpenTripCard(
            trip: open,
            onEnd: () => _open(context, TripFormScreen(mode: 'end', trip: open)),
            onCancel: () => _cancelTrip(context, state, open),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _open(context, const TripFormScreen(mode: 'full')),
            icon: const Icon(Icons.edit_calendar_outlined),
            label: const Text('Log a finished trip'),
          ),
        ] else ...[
          FilledButton.icon(
            onPressed: () => _open(context, const TripFormScreen(mode: 'start')),
            icon: const Icon(Icons.play_arrow_rounded, size: 26),
            label: const Text('Start a trip'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _open(context, const TripFormScreen(mode: 'full')),
            icon: const Icon(Icons.edit_calendar_outlined),
            label: const Text('Log a finished trip'),
          ),
        ],
        const SizedBox(height: 24),
        SectionTitle(
          'Recent trips',
          trailing: recent.isEmpty || onSeeAll == null
              ? null
              : TextButton(onPressed: onSeeAll, child: const Text('See all')),
        ),
        if (recent.isEmpty)
          const Surface(
            child: EmptyState(
              icon: Icons.route_outlined,
              title: 'No trips yet',
              body: 'Start a trip when you leave. You will need the meter reading and a photo of the meter.',
            ),
          )
        else
          for (final t in recent)
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
    );
  }
}

// ------------------------------------------------------------------ month hero

/// The month's km on odometer drums, with the limit as a road below.
class _MonthHero extends StatelessWidget {
  final String month;
  final MonthSummary sum;
  final AppSettings settings;

  const _MonthHero({required this.month, required this.sum, required this.settings});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final limit = settings.limitKm;
    final used = sum.gaugeKm;
    final left = limit - used;
    final caption = settings.scope == 'project' ? 'km on your busiest project' : 'km used';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.drum,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.drumStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fmtMonthLong(month),
            style: tt.bodyMedium?.copyWith(color: AppColors.onDrumMuted, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          OdometerDrums(value: used, rollIn: true),
          const SizedBox(height: 10),
          Text(
            '$caption of ${fmtKm(limit)}',
            style: tt.bodyMedium?.copyWith(color: AppColors.onDrumMuted),
          ),
          const SizedBox(height: 16),
          LimitRoad(used: used, limit: limit),
          const SizedBox(height: 14),
          Divider(color: AppColors.drumStroke, height: 1),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _DrumFigure(
                  value: fmtRs(sum.amount),
                  label: 'payable within limit',
                  color: AppColors.greenLight,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: left >= 0
                    ? _DrumFigure(value: '${fmtKm(left)} km', label: 'left this month', color: AppColors.onDrum)
                    : _DrumFigure(value: '${fmtKm(-left)} km', label: 'above the limit', color: AppColors.amber),
              ),
            ],
          ),
          if (left < 0) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 18, color: AppColors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Km above the limit are paid only after District Integrator approval.',
                    style: tt.bodySmall?.copyWith(color: AppColors.onDrumMuted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DrumFigure extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _DrumFigure({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: numStyle(28, weight: FontWeight.w700, color: color)),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.onDrumMuted)),
      ],
    );
  }
}

// ------------------------------------------------------------------ open trip

class _OpenTripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  const _OpenTripCard({required this.trip, required this.onEnd, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final started = DateTime.parse(trip.start.at);
    final elapsed = DateTime.now().difference(started);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.tertiary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const StatusPill('On a trip', kind: PillKind.open),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'since ${fmtTime(trip.start.at)}  ·  ${fmtElapsed(elapsed.isNegative ? Duration.zero : elapsed)}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RouteLine(from: trip.from, to: trip.to, large: true, toLines: 2),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fmtKm(trip.start.km), style: numStyle(28, weight: FontWeight.w700, color: cs.onSurface)),
                  const SizedBox(height: 4),
                  Text('opening reading', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  '${trip.project}\n${trip.vehicle}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onEnd,
            icon: const Icon(Icons.flag_rounded),
            label: const Text('End trip'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
            child: const Text('Cancel this trip'),
          ),
        ],
      ),
    );
  }
}
