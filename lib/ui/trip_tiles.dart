import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/trip.dart';
import '../services/app_state.dart';
import '../services/trip_rules.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

// ------------------------------------------------------------------ list tile

/// One trip in a list: where it went, which project, how far.
class TripTile extends StatelessWidget {
  final Trip trip;
  final List<String> flags;
  final bool showDate;
  final VoidCallback? onTap;

  const TripTile({super.key, required this.trip, this.flags = const [], this.showDate = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final cancelled = trip.status == 'cancelled';
    final open = trip.status == 'open';

    final meta = <String>[
      if (showDate) fmtDay(trip.date),
      trip.project,
    ].join('  ·  ');

    Widget figure;
    if (open) {
      figure = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('open', style: tt.titleMedium?.copyWith(color: cs.onTertiaryContainer)),
          const SizedBox(height: 2),
          Text(fmtKm(trip.start.km), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      );
    } else {
      figure = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            cancelled ? '0' : fmtKm(trip.km ?? 0),
            style: numStyle(28, weight: FontWeight.w700, color: cancelled ? cs.outline : cs.onSurface),
          ),
          const SizedBox(height: 3),
          Text('km', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      );
    }

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: open ? cs.tertiary : cs.outlineVariant, width: open ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.to,
                      style: tt.titleMedium?.copyWith(
                        decoration: cancelled ? TextDecoration.lineThrough : null,
                        color: cancelled ? cs.onSurfaceVariant : cs.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'from ${trip.from}',
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      meta,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (open) const StatusPill('On a trip', kind: PillKind.open),
                        if (cancelled) const StatusPill('Cancelled', kind: PillKind.cancelled),
                        if (trip.status == 'closed') const StatusPill('Locked', kind: PillKind.locked),
                        for (final f in flags) StatusPill(f, kind: PillKind.flag),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              figure,
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ detail sheet

/// Opens the full record of one trip.
Future<void> showTripDetail(BuildContext context, String tripId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (ctx, controller) => TripDetail(tripId: tripId, controller: controller),
    ),
  );
}

class TripDetail extends StatelessWidget {
  final String tripId;
  final ScrollController? controller;

  const TripDetail({super.key, required this.tripId, this.controller});

  Future<void> _addNote(BuildContext context, AppState state, Trip t) async {
    final ctl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The entry stays locked. The note is added below it with the time.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () {
              final v = ctl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Add note'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (text != null) await state.addNote(t, text);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Trip? t;
    for (final x in state.trips) {
      if (x.id == tripId) t = x;
    }
    if (t == null) {
      return const Center(child: Text('This entry is no longer in the log book.'));
    }
    final trip = t;
    final settings = state.settings;
    // Late entry, meter reset and approval each get their own note below. Show the rest as pills.
    final flags = tripFlags(trip, settings).where((f) => f == 'Photo not fresh' || f == 'High km').toList();
    final cancelled = trip.status == 'cancelled';
    final open = trip.status == 'open';
    final end = trip.end;
    final prior = trip.prior;

    String? duration;
    if (end != null) {
      final d = DateTime.parse(end.at).difference(DateTime.parse(trip.start.at));
      if (!d.isNegative) duration = fmtElapsed(d);
    }

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Row(
          children: [
            Expanded(child: Text(fmtDayYear(trip.date), style: tt.titleLarge)),
            if (open)
              const StatusPill('On a trip', kind: PillKind.open)
            else if (cancelled)
              const StatusPill('Cancelled', kind: PillKind.cancelled)
            else
              const StatusPill('Locked', kind: PillKind.locked),
          ],
        ),
        const SizedBox(height: 16),
        RouteLine(from: trip.from, to: trip.to, large: true, toLines: 3),
        if (!cancelled && !open) ...[
          const SizedBox(height: 18),
          Surface(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: cs.surfaceContainerLow,
            child: Row(
              children: [
                Expanded(child: StatCell(label: 'km', value: trip.km == null ? '—' : fmtKm(trip.km!))),
                Expanded(
                  child: StatCell(
                    label: 'at ₹${_num(settings.rate)}/km',
                    value: trip.km == null ? '—' : fmtRs(trip.km! * settings.rate),
                  ),
                ),
                Expanded(child: StatCell(label: 'on the road', value: duration ?? '—')),
              ],
            ),
          ),
        ],
        if (cancelled && trip.cancel != null) ...[
          const SizedBox(height: 18),
          _Callout(
            icon: Icons.block,
            title: 'Cancelled',
            body: '${trip.cancel!['reason'] ?? ''}',
          ),
        ],
        const SizedBox(height: 22),
        Text('Odometer', style: tt.titleMedium),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _ReadingCard(label: 'Opening', reading: trip.start)),
            const SizedBox(width: 12),
            Expanded(
              child: end == null
                  ? _ReadingCard.pending(label: 'Closing', text: cancelled ? 'No closing reading' : 'Not ended yet')
                  : _ReadingCard(label: 'Closing', reading: end),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text('The work', style: tt.titleMedium),
        const SizedBox(height: 10),
        _Info('Task', trip.task),
        _Info('Type of work', trip.activity),
        _Info('Project', trip.project),
        _Info('Vehicle', trip.vtype.isEmpty ? trip.vehicle : '${trip.vehicle}  ·  ${trip.vtype}'),
        if (end != null && (end.returnTo ?? '').isNotEmpty) _Info('Returned to', end.returnTo!),
        if (end != null && (end.remarks ?? '').isNotEmpty) _Info('Remarks', end.remarks!),
        if (flags.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final f in flags) StatusPill(f, kind: PillKind.flag)]),
        ],
        if (trip.late != null) ...[
          const SizedBox(height: 14),
          _Callout(icon: Icons.schedule, title: 'Late entry', body: '${trip.late!['reason'] ?? ''}'),
        ],
        if (trip.meterReset != null) ...[
          const SizedBox(height: 12),
          _Callout(icon: Icons.speed, title: 'Meter was reset or replaced', body: '${trip.meterReset!['reason'] ?? ''}'),
        ],
        if (prior != null) ...[
          const SizedBox(height: 12),
          prior['none'] == true
              ? const _Callout(
                  icon: Icons.report_problem_outlined,
                  title: 'No prior approval',
                  body: 'This trip went above the monthly limit without approval taken before travelling.',
                  warn: true,
                )
              : _Callout(
                  icon: Icons.verified_outlined,
                  title: 'Approved before travelling',
                  body: [
                    '${prior['by'] ?? ''}',
                    '${prior['mode'] ?? ''}',
                    if ('${prior['date'] ?? ''}'.isNotEmpty) fmtDate('${prior['date']}'),
                    if ('${prior['ref'] ?? ''}'.isNotEmpty) '${prior['ref']}',
                  ].where((e) => e.isNotEmpty).join('  ·  '),
                ),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(child: Text('Notes', style: tt.titleMedium)),
            if (!open)
              TextButton.icon(
                onPressed: () => _addNote(context, state, trip),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add a note'),
              ),
          ],
        ),
        if (trip.notes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              open ? 'You can add notes once the trip is locked.' : 'No notes on this entry.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          )
        else
          for (final n in trip.notes)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Surface(
                padding: const EdgeInsets.all(12),
                color: cs.surfaceContainerLow,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.text, style: tt.bodyMedium),
                    const SizedBox(height: 4),
                    Text(fmtDateTime(n.at), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 22),
        _SealBlock(trip: trip),
      ],
    );
  }
}

String _num(num n) => n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(2);

class _Info extends StatelessWidget {
  final String label;
  final String value;
  const _Info(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: tt.bodyLarge),
        ],
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool warn;

  const _Callout({required this.icon, required this.title, required this.body, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bg = warn ? cs.errorContainer : cs.tertiaryContainer;
    final fg = warn ? cs.onErrorContainer : cs.onTertiaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.titleSmall?.copyWith(color: fg)),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(body, style: tt.bodyMedium?.copyWith(color: fg)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  final String label;
  final Reading? reading;
  final String? pendingText;

  const _ReadingCard({required this.label, required Reading this.reading}) : pendingText = null;
  const _ReadingCard.pending({required this.label, required String text})
      : reading = null,
        pendingText = text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final r = reading;
    return Surface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          if (r == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(pendingText ?? '', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            )
          else ...[
            Text(fmtKm(r.km), style: numStyle(30, weight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text(fmtTime(r.at), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            _PhotoThumb(photoKey: r.photoKey, caption: '$label reading'),
          ],
        ],
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final String? photoKey;
  final String caption;
  const _PhotoThumb({required this.photoKey, required this.caption});

  Widget _placeholder(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      color: cs.surfaceContainer,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined, color: cs.outline),
          const SizedBox(height: 4),
          Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final key = photoKey;
    Widget inner;
    VoidCallback? onTap;
    if (key == null || key.isEmpty) {
      inner = _placeholder(context, 'No photo');
    } else {
      final file = File(context.read<AppState>().storage.photoPath(key));
      inner = Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (ctx, _, __) => _placeholder(ctx, 'Photo not on this phone'),
      );
      onTap = () => showDialog<void>(
            context: context,
            builder: (ctx) => Dialog(
              insetPadding: const EdgeInsets.all(12),
              backgroundColor: Colors.black,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Stack(
                children: [
                  InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, _, __) => _placeholder(ctx, 'Photo not on this phone'),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      tooltip: 'Close',
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            ),
          );
    }
    return Semantics(
      label: caption,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(aspectRatio: 4 / 3, child: inner),
        ),
      ),
    );
  }
}

class _SealBlock extends StatelessWidget {
  final Trip trip;
  const _SealBlock({required this.trip});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (trip.status == 'open' || trip.hash == null) {
      return Surface(
        color: cs.surfaceContainerLow,
        child: Row(
          children: [
            Icon(Icons.lock_open, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Not locked yet. The entry locks when you end the trip.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }
    final ok = sealIntact(trip);
    final short = trip.hash!.length > 12 ? trip.hash!.substring(0, 12) : trip.hash!;
    return Surface(
      color: ok ? cs.primaryContainer.withAlpha(110) : cs.errorContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.verified_user : Icons.gpp_bad, color: ok ? cs.primary : cs.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ok ? 'Locked, seal intact' : 'Seal does not match', style: tt.titleSmall),
                const SizedBox(height: 2),
                Text(
                  ok
                      ? 'Locked ${trip.lockedAt == null ? '' : fmtDateTime(trip.lockedAt!)}. Nothing in this entry has changed since.'
                      : 'Something in this entry changed after it was locked. Show this to your Block Integrator.',
                  style: tt.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Entry ${trip.chainPos ?? '-'}  ·  seal $short',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
