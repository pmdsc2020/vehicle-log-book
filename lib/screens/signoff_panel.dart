import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/report.dart';
import '../services/app_state.dart';
import '../services/report_service.dart';
import '../services/trip_rules.dart';
import '../ui/format.dart';
import '../ui/motion.dart';
import '../ui/signoff_widgets.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'report_flow.dart';

/// The sign-off part of the Report tab: send the month, follow it from desk to desk, take back a
/// returned report and send it again.
class SignoffPanel extends StatelessWidget {
  final String month;
  const SignoffPanel({super.key, required this.month});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final report = state.myReport(month);
    if (report == null) return _NotSent(month: month);
    return _InProgress(report: report);
  }
}

Future<void> _sendReport(BuildContext context, String month, {required bool again}) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final trips = state.tripsOfMonth(month);
  final sum = summarise(trips, state.settings);
  final monthOver = month.compareTo(currentMonth()) < 0;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(again ? 'Send ${fmtMonthLong(month)} again?' : 'Send ${fmtMonthLong(month)} for sign-off?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${sum.trips} ${sum.trips == 1 ? 'trip' : 'trips'}, ${fmtKm(sum.km)} km, '
            '${fmtRs(sum.amount)} within the limit.',
          ),
          const SizedBox(height: 10),
          Text(
            'The trips and meter photos are packed into one file and sealed. '
            'You then send the file to the Block Integrator on WhatsApp or email.',
          ),
          const SizedBox(height: 10),
          Text(
            monthOver
                ? 'After sending, no trips can be added to ${fmtMonthLong(month)} unless the report is returned.'
                : '${fmtMonthLong(month)} is not over yet. After sending, no trips can be added to it unless the report is returned.',
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Seal and send')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  ReportPackage pkg;
  try {
    pkg = await withBusy(context, 'Sealing the report', () => state.submitReport(month));
  } on ReportError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (!context.mounted) return;
  await shareReport(context, pkg);
}

// ------------------------------------------------------------------ before sending

class _NotSent extends StatelessWidget {
  final String month;
  const _NotSent({required this.month});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final blocker = reportBlocker(state.tripsOfMonth(month));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                  'Your report goes to the Block Integrator first, then the Accountant, then the District Integrator. '
                  'Each one checks it on their own phone and signs.',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              if (blocker != null) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(AppIcons.info, size: 18, color: cs.amberText),
                      const SizedBox(width: 8),
                      Expanded(child: Text(blocker, style: tt.bodyMedium)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlowButton(
          icon: AppIcons.send,
          label: 'Send report for sign-off',
          onPressed: blocker == null ? () => _sendReport(context, month, again: false) : null,
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => openReportFile(context),
          icon: const Icon(AppIcons.openFile, size: 20),
          label: const Text('Open a signed file'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ after sending

class _InProgress extends StatelessWidget {
  final ReportPackage report;
  const _InProgress({required this.report});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final st = statusOf(report);
    final last = st.last;
    final next = st.nextStep;

    String message;
    switch (st.stage) {
      case ReportStage.approved:
        message = 'Approved. Keep the signed file for your records.';
        break;
      case ReportStage.returned:
        message = '${last?.name ?? 'The reviewer'} (${stepRoleLabel(last?.step ?? '')}) sent it back. '
            'Read the note, add a note to a trip if it helps, then send it again.';
        break;
      default:
        message = 'Waiting for the ${stepRoleLabel(next ?? 'bi')}. Send them the file. '
            'When they have signed, ask them to send it back to you so the sign-off shows here.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Surface(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        report.revision > 1 ? 'Version ${report.revision}' : 'Sent ${fmtDateTime(report.submittedAt)}',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                    reportPill(report),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ApprovalChain(done: st.done, returnedAt: st.returnedAt),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(message, style: tt.bodyMedium),
              ),
              if (st.stage == ReportStage.approved) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    children: [
                      LedgerRow(label: 'Km approved', value: '${fmtKm(payableKm(report))} km'),
                      LedgerRow(
                        label: 'Payable',
                        value: fmtRs(payableAmount(report)),
                        strong: true,
                        valueColor: cs.primary,
                      ),
                      if (report.summary.excess > 0)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            approvalOf(report)?.excessApproved == true
                                ? 'The ${fmtKm(report.summary.excess)} km above the limit were approved.'
                                : 'The ${fmtKm(report.summary.excess)} km above the limit were not approved.',
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Divider(color: cs.outlineVariant, height: 1),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: SignoffTimeline(signoffs: report.signoffs),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (st.stage == ReportStage.returned)
          GlowButton(
            icon: AppIcons.send,
            label: 'Send again',
            onPressed: () => _sendReport(context, report.month, again: true),
          )
        else
          GlowButton(
            icon: AppIcons.share,
            label: st.stage == ReportStage.approved ? 'Share the approved copy' : 'Send the file again',
            onPressed: () => shareReport(context, report),
          ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => openReportFile(context),
          icon: const Icon(AppIcons.openFile, size: 20),
          label: const Text('Open a signed file'),
        ),
      ],
    );
  }
}
