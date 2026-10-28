import 'package:flutter/material.dart';

import '../models/report.dart';
import '../services/report_service.dart';
import '../services/trip_rules.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// The pill that says where a report stands. [myStep] is the step this person signs: when the
/// report is waiting for them the pill says so.
StatusPill reportPill(ReportPackage p, {String? myStep}) {
  final st = statusOf(p);
  if (myStep != null && st.nextStep == myStep) {
    return const StatusPill('Needs your sign-off', kind: PillKind.open);
  }
  switch (st.stage) {
    case ReportStage.returned:
      return const StatusPill('Returned', kind: PillKind.flag);
    case ReportStage.approved:
      return const StatusPill('Approved', kind: PillKind.locked, icon: AppIcons.approved);
    default:
      return StatusPill(stageLabel(st), kind: PillKind.info);
  }
}

/// Who signed the report, in order, with what they wrote.
class SignoffTimeline extends StatelessWidget {
  final List<SignOff> signoffs;
  const SignoffTimeline({super.key, required this.signoffs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < signoffs.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == signoffs.length - 1 ? 0 : 14),
            child: _SignoffRow(signoff: signoffs[i]),
          ),
      ],
    );
  }
}

class _SignoffRow extends StatelessWidget {
  final SignOff signoff;
  const _SignoffRow({required this.signoff});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final s = signoff;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: s.returned ? cs.errorContainer : cs.primaryContainer,
          child: s.returned
              ? RotatedBox(quarterTurns: 2, child: Icon(AppIcons.arrow, size: 16, color: cs.onErrorContainer))
              : Icon(s.step == 'submit' ? AppIcons.send : AppIcons.check, size: 16, color: cs.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${signoffVerb(s)} by ${s.name}', style: tt.titleSmall),
              Text(
                '${stepRoleLabel(s.step)}  ·  ${fmtDateTime(s.at)}',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (s.excessApproved)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Also approved the km above the limit.', style: tt.bodySmall),
                ),
              if (s.remarks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Surface(
                    padding: const EdgeInsets.all(10),
                    radius: 14,
                    color: cs.surfaceContainerLow,
                    child: Text(s.remarks, style: tt.bodyMedium),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The checks run on a report, one line each.
class CheckList extends StatelessWidget {
  final PackageCheck check;
  const CheckList({super.key, required this.check});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in check.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    l.state == CheckState.ok ? AppIcons.ok : (l.state == CheckState.warn ? AppIcons.warn : AppIcons.sealBad),
                    size: 18,
                    color: l.state == CheckState.ok ? cs.primary : (l.state == CheckState.warn ? cs.amberText : cs.error),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.title, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      if (l.detail.isNotEmpty)
                        Text(l.detail, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One report in a list: who sent it, which month, how much, where it stands.
class ReportTile extends StatelessWidget {
  final ReportPackage report;
  final String? myStep;
  final VoidCallback onTap;

  const ReportTile({super.key, required this.report, required this.onTap, this.myStep});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final p = report;
    final st = statusOf(p);
    final km = fmtKm(p.summary.km);
    final money = fmtRs(st.stage == ReportStage.approved ? payableAmount(p) : p.summary.within * p.policy.rate);
    return Surface(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      semanticLabel: '${p.staff.name}, ${fmtMonthLong(p.month)}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
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
              style: tt.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.staff.name, style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${fmtMonthLong(p.month)}${p.revision > 1 ? '  ·  Version ${p.revision}' : ''}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('$km km', style: numStyle(18, weight: FontWeight.w600, color: cs.onSurface)),
                    const SizedBox(width: 10),
                    Text(money, style: numStyle(18, weight: FontWeight.w600, color: cs.primary)),
                  ],
                ),
                const SizedBox(height: 8),
                reportPill(p, myStep: myStep),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Icon(AppIcons.chevron, size: 20, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
