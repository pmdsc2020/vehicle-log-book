import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/report.dart';
import '../models/trip.dart';
import '../services/app_state.dart';
import '../services/report_service.dart';
import '../services/trip_rules.dart';
import '../ui/format.dart';
import '../ui/motion.dart';
import '../ui/signoff_widgets.dart';
import '../ui/theme.dart';
import '../ui/trip_tiles.dart';
import '../ui/widgets.dart';
import 'report_flow.dart';
import 'report_screen.dart' show ProjectBar;

String _firstName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.isEmpty || parts.first.isEmpty ? 'the staff member' : parts.first;
}

/// Who the file goes to after this sign-off.
String _recipientOf(ReportPackage p) {
  switch (statusOf(p).stage) {
    case ReportStage.withBi:
      return 'the Block Integrator';
    case ReportStage.withAcc:
      return 'the Accountant';
    case ReportStage.withDi:
      return 'the District Integrator';
    default:
      return p.staff.name;
  }
}

// ------------------------------------------------------------------ the Review tab

/// Reports sent to this person to check, verify or approve, and the ones they have passed on.
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  void _open(BuildContext context, ReportPackage p) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ReportReviewScreen(reportKey: p.key)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final me = state.profile!;
    final step = stepOfRole(me.role);
    final received = state.received;
    final waiting = received.where((r) => step != null && statusOf(r).nextStep == step).toList();
    final others = received.where((r) => !waiting.contains(r)).toList();

    return ListView(
      padding: pagePadding(context),
      children: [
        Text('Review', style: tt.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'You sign as ${stepRoleLabel(step ?? me.role)}.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Surface(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Got a report to sign?', style: tt.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Staff send it on WhatsApp or email as a file. Save the file on your phone, then open it here. '
                'The app checks every seal and photo before you sign.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              GlowButton(
                icon: AppIcons.openFile,
                label: 'Open a report file',
                onPressed: () => openReportFile(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (received.isEmpty)
          const Surface(
            child: EmptyState(
              icon: AppIcons.inbox,
              title: 'No reports yet',
              body: 'Reports you open appear here, with the ones waiting for your signature first.',
            ),
          ),
        if (waiting.isNotEmpty) ...[
          SectionTitle('Waiting for you', trailing: StatusPill('${waiting.length}', kind: PillKind.flag)),
          for (final r in waiting)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ReportTile(report: r, myStep: step, onTap: () => _open(context, r)),
            ),
        ],
        if (others.isNotEmpty) ...[
          const SectionTitle('Passed on'),
          for (final r in others)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ReportTile(report: r, myStep: step, onTap: () => _open(context, r)),
            ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------ one report

/// A report in full: the checks, the figures, every trip with its photos, and the sign-off.
class ReportReviewScreen extends StatefulWidget {
  final String reportKey;
  const ReportReviewScreen({super.key, required this.reportKey});

  @override
  State<ReportReviewScreen> createState() => _ReportReviewScreenState();
}

class _ReportReviewScreenState extends State<ReportReviewScreen> {
  final TextEditingController _remarks = TextEditingController();
  Future<PackageCheck>? _check;
  String _checkedFor = '';
  bool _excess = false;
  bool _busy = false;

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _sign(ReportPackage p, String decision) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final me = state.profile!;
    final note = _remarks.text.trim();
    final step = stepOfRole(me.role) ?? me.role;
    if (decision == 'return' && note.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Write why you are sending it back.')));
      return;
    }
    final staffName = _firstName(p.staff.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(decision == 'return'
            ? 'Send back to $staffName?'
            : (step == 'di' ? 'Approve this report?' : (step == 'acc' ? 'Mark as verified?' : 'Mark as checked?'))),
        content: Text(
          'You sign as ${me.name}, ${stepRoleLabel(step)}. '
          'Your name, the time and your remarks are sealed onto the report. You cannot change it afterwards.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(decision == 'return' ? 'Send back' : 'Sign'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    ReportPackage signed;
    try {
      signed = await state.signReportAs(p, decision: decision, remarks: note, excessApproved: _excess);
    } on ReportError catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _remarks.clear();

    final to = _recipientOf(signed);
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(AppIcons.ok, color: Theme.of(ctx).colorScheme.primary),
        title: const Text('Signed'),
        content: Text('Now send the file to $to. They open it in the app to carry on.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send now')),
        ],
      ),
    );
    if (send == true && mounted) await shareReport(context, signed);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final p = state.reportByKey(widget.reportKey);
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Report')),
        body: const Center(child: Text('This report is no longer on this phone.')),
      );
    }

    final sig = '${p.key}:${p.signoffs.length}';
    if (_checkedFor != sig) {
      _checkedFor = sig;
      _check = state.checkReport(p);
    }

    final me = state.profile!;
    final myStep = stepOfRole(me.role);
    final st = statusOf(p);
    final myTurn = myStep != null && st.nextStep == myStep && p.staff.id != me.id;
    final settings = p.policy.toSettings();
    final sum = summarise(p.trips, settings);
    final flagged = p.trips.where((t) => t.status != 'cancelled' && tripFlags(t, settings).isNotEmpty).toList();
    final projects = sum.kmByProject.keys.toList()
      ..sort((a, b) => (sum.kmByProject[b] ?? 0).compareTo(sum.kmByProject[a] ?? 0));
    final maxKm = projects.isEmpty ? 1 : (sum.kmByProject[projects.first] ?? 1);
    final scopeProject = settings.scope == 'project';

    void openTrip(Trip trip) => showReportTripDetail(
          context,
          trip,
          settings,
          (key) => state.storage.reportPhotoFile(p, key),
        );

    return Scaffold(
      appBar: AppBar(title: Text('${fmtMonthShort(p.month)} report')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 28 + MediaQuery.paddingOf(context).bottom),
        children: [
          // Who and which month.
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: AppGradients.brand(cs.brightness),
                        ),
                      ),
                      child: Text(
                        initialsOf(p.staff.name),
                        style: tt.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.staff.name, style: tt.titleMedium),
                          Text(
                            [p.staff.designation, p.staff.block].where((e) => e.isNotEmpty).join(', '),
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: Text(fmtMonthLong(p.month), style: tt.headlineSmall)),
                    reportPill(p, myStep: myStep),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Sent ${fmtDateTime(p.submittedAt)}${p.revision > 1 ? '  ·  Version ${p.revision}' : ''}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (p.replaces != null) ...[
            const SizedBox(height: 12),
            Surface(
              color: cs.surfaceContainerLow,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(AppIcons.info, size: 20, color: cs.amberText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sent again after it was returned', style: tt.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          '${p.replaces!.name} (${stepRoleLabel(p.replaces!.step)}) wrote: ${p.replaces!.remarks}',
                          style: tt.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // The checks.
          FutureBuilder<PackageCheck>(
            future: _check,
            builder: (context, snap) {
              final c = snap.data;
              if (c == null) {
                return const Surface(
                  child: Row(
                    children: [
                      SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3)),
                      SizedBox(width: 14),
                      Expanded(child: Text('Checking the seals and photos')),
                    ],
                  ),
                );
              }
              return Surface(
                color: c.ok ? cs.primaryContainer.withAlpha(110) : cs.errorContainer,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(c.ok ? AppIcons.sealOk : AppIcons.sealBad, color: c.ok ? cs.primary : cs.error),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            c.ok ? (c.hasWarnings ? 'Passed, with a note' : 'Every check passed') : 'Do not sign: this report fails a check',
                            style: tt.titleSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    CheckList(check: c),
                  ],
                ),
              );
            },
          ),

          // The figures.
          const SizedBox(height: 8),
          const SectionTitle('Statement'),
          Surface(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LedgerRow(label: 'Trips', value: '${sum.trips}'),
                LedgerRow(label: 'Km travelled', value: fmtKm(sum.km)),
                LedgerRow(
                  label: 'Within ${fmtKm(settings.limitKm)} km${scopeProject ? ' per project' : ''}',
                  value: '${fmtKm(sum.within)} km',
                ),
                LedgerRow(
                  label: 'Above the limit',
                  value: '${fmtKm(sum.excess)} km',
                  valueColor: sum.excess > 0 ? cs.amberText : null,
                ),
                const SizedBox(height: 4),
                Divider(color: cs.outlineVariant),
                const SizedBox(height: 4),
                LedgerRow(label: 'Payable within limit', value: fmtRs(sum.amount), strong: true, valueColor: cs.primary),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${fmtKm(sum.within)} km at ₹${settings.rate == settings.rate.roundToDouble() ? settings.rate.round() : settings.rate.toStringAsFixed(2)} a km.'
                    '${sum.excess > 0 ? ' The ${fmtKm(sum.excess)} km above the limit are paid only if the District Integrator approves them.' : ''}',
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
                  for (final name in projects)
                    ProjectBar(
                      name: name,
                      km: sum.kmByProject[name] ?? 0,
                      trips: sum.tripsByProject[name] ?? 0,
                      fraction: (sum.kmByProject[name] ?? 0) / maxKm,
                    ),
                ],
              ),
            ),
          ],

          // The trips.
          if (flagged.isNotEmpty) ...[
            const SizedBox(height: 8),
            SectionTitle('Worth a second look', trailing: StatusPill('${flagged.length}', kind: PillKind.flag)),
            for (final t in flagged)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TripTile(trip: t, showDate: true, flags: tripFlags(t, settings), onTap: () => openTrip(t)),
              ),
          ],
          const SizedBox(height: 8),
          SectionTitle('All trips', trailing: Text('${p.trips.length}', style: tt.titleMedium)),
          for (final t in p.trips)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TripTile(trip: t, showDate: true, flags: tripFlags(t, settings), onTap: () => openTrip(t)),
            ),

          // Sign-off.
          const SizedBox(height: 8),
          const SectionTitle('Sign-off'),
          Surface(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ApprovalChain(done: st.done, returnedAt: st.returnedAt),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: SignoffTimeline(signoffs: p.signoffs),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FutureBuilder<PackageCheck>(
            future: _check,
            builder: (context, snap) {
              final c = snap.data;
              if (c == null) return const SizedBox.shrink();
              if (!c.ok) {
                return Text(
                  'Do not sign this report. Ask ${_firstName(p.staff.name)} to send it again from their phone.',
                  style: tt.bodyMedium?.copyWith(color: cs.error),
                );
              }
              if (myTurn && myStep != null) return _signPanel(p, myStep);
              return _afterPanel(p);
            },
          ),
        ],
      ),
    );
  }

  Widget _signPanel(ReportPackage p, String step) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final staffName = _firstName(p.staff.name);
    final excess = p.summary.excess;
    final extra = excess * p.policy.rate;
    final forwardLabel = step == 'di'
        ? 'Approve'
        : (step == 'acc' ? 'Verified, send to District Integrator' : 'Checked, send to Accountant');
    return Surface(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your sign-off', style: tt.titleMedium),
          const SizedBox(height: 4),
          Text(
            step == 'di'
                ? 'Approve the report to release the payment, or send it back with a note.'
                : 'Look through the trips and photos. Sign when you are satisfied, or send it back with a note.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _remarks,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Remarks', hintText: 'Needed only if you send it back'),
          ),
          if (step == 'di' && excess > 0) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _excess,
              onChanged: (v) => setState(() => _excess = v),
              title: Text('Also approve the ${fmtKm(excess)} km above the limit'),
              subtitle: Text('${fmtRs(extra)} more, ${fmtRs(p.summary.amount + extra)} in all'),
            ),
          ],
          const SizedBox(height: 14),
          GlowButton(
            icon: AppIcons.check,
            label: forwardLabel,
            busy: _busy,
            onPressed: _busy ? null : () => _sign(p, step == 'di' ? 'approve' : 'forward'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _sign(p, 'return'),
            icon: RotatedBox(quarterTurns: 2, child: Icon(AppIcons.arrow, size: 20, color: cs.primary)),
            label: Text('Send back to $staffName'),
          ),
        ],
      ),
    );
  }

  Widget _afterPanel(ReportPackage p) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final st = statusOf(p);
    final signedByMe = p.signoffs.any((s) => s.userId == context.read<AppState>().profile!.id && s.step != 'submit');
    String text;
    switch (st.stage) {
      case ReportStage.approved:
        text = 'Approved. The signed file goes back to ${_firstName(p.staff.name)}.';
        break;
      case ReportStage.returned:
        text = 'Sent back to ${_firstName(p.staff.name)} to fix. They send a new version when ready.';
        break;
      default:
        text = signedByMe
            ? 'You have signed. Send the file on to ${_recipientOf(p)}.'
            : 'This report is with ${_recipientOf(p)} now, not with you.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (signedByMe)
          GlowButton(
            icon: AppIcons.share,
            label: 'Send the file to ${_recipientOf(p)}',
            onPressed: () => shareReport(context, p),
          )
        else
          OutlinedButton.icon(
            onPressed: () => shareReport(context, p),
            icon: const Icon(AppIcons.share, size: 20),
            label: const Text('Share the file'),
          ),
      ],
    );
  }
}
