import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/trip.dart';
import '../services/app_state.dart';
import '../services/trip_rules.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _erase(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erase all data?'),
        content: const Text(
          'This removes every trip, photo and setting from this phone. Locked entries cannot be recovered.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep my data')),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(64, 44),
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Erase everything'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) await state.eraseAll();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final p = state.profile!;
    final s = state.settings;

    final sealed = state.trips.where((Trip t) => t.hash != null).toList();
    final broken = sealed.where((t) => !sealIntact(t)).length;

    final mode = state.themeMode;
    final modeKey = mode == ThemeMode.light ? 'light' : (mode == ThemeMode.dark ? 'dark' : 'system');

    return ListView(
      padding: pagePadding(context),
      children: [
        Text('Settings', style: tt.headlineSmall),
        const SizedBox(height: 14),
        Surface(
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: AppGradients.brand(cs.brightness),
                  ),
                  boxShadow: [BoxShadow(color: cs.primary.withAlpha(60), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Text(
                  initialsOf(p.name),
                  style: tt.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: tt.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      [p.designation, p.block].where((e) => e.isNotEmpty).join('  ·  '),
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        StatusPill(roleLabel(p.role), kind: PillKind.info, icon: AppIcons.role),
                        StatusPill('Code ${p.id}', kind: PillKind.info),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const SectionTitle('Vehicles'),
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: p.vehicles.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No vehicle saved. You can type the number when you start a trip.',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < p.vehicles.length; i++) ...[
                      if (i > 0) const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                p.vehicles[i].type == 'Four-wheeler' ? AppIcons.fourWheeler : AppIcons.twoWheeler,
                                color: cs.onPrimaryContainer,
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Text(p.vehicles[i].no, style: tt.titleSmall)),
                            Text(p.vehicles[i].type, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 8),
        const SectionTitle('Office rules'),
        Surface(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              LedgerRow(label: 'Monthly limit', value: '${fmtKm(s.limitKm)} km'),
              LedgerRow(label: 'Rate', value: '₹${s.rate == s.rate.roundToDouble() ? s.rate.round() : s.rate} a km'),
              LedgerRow(label: 'Limit applies to', value: s.scope == 'project' ? 'each project' : 'each person'),
              LedgerRow(label: 'Late entry after', value: '${s.lateDays} days'),
              LedgerRow(label: 'High km above', value: '${fmtKm(s.highKm)} km'),
              LedgerRow(label: 'Photo must be taken within', value: '${s.photoMaxAge} min'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const SectionTitle('Appearance'),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment<String>(value: 'system', label: Text('Phone'), icon: Icon(AppIcons.phoneTheme)),
            ButtonSegment<String>(value: 'light', label: Text('Light'), icon: Icon(AppIcons.sun)),
            ButtonSegment<String>(value: 'dark', label: Text('Dark'), icon: Icon(AppIcons.moon)),
          ],
          selected: {modeKey},
          onSelectionChanged: (v) => state.setThemeMode(v.first),
        ),
        const SizedBox(height: 16),
        const SectionTitle('Integrity'),
        Surface(
          color: broken == 0 ? cs.primaryContainer.withAlpha(110) : cs.errorContainer,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(broken == 0 ? AppIcons.sealOk : AppIcons.sealBad, color: broken == 0 ? cs.primary : cs.error),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sealed.isEmpty
                          ? 'No locked entries yet'
                          : (broken == 0
                              ? 'All ${sealed.length} locked entries are intact'
                              : '$broken of ${sealed.length} locked entries do not match their seal'),
                      style: tt.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Each entry is sealed when you save it and linked to the one before. '
                      'Any later change breaks the seal.',
                      style: tt.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle('Data on this phone'),
        OutlinedButton.icon(
          onPressed: () => _erase(context, state),
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.error,
            side: BorderSide(color: cs.error.withAlpha(140)),
          ),
          icon: const Icon(AppIcons.erase),
          label: const Text('Erase all data'),
        ),
        const SizedBox(height: 6),
        Text(
          'Removes trips, photos and settings from this phone.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Center(
          child: Column(
            children: [
              const LogoMark(size: 40),
              const SizedBox(height: 8),
              Text('Vehicle Log Book 1.0', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              Text(s.org, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
