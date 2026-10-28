import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/report.dart';
import '../services/app_state.dart';
import '../services/report_service.dart';
import '../services/trip_rules.dart';
import '../ui/format.dart';
import '../ui/signoff_widgets.dart';
import '../ui/theme.dart';
import 'review_screen.dart';

/// Shows a spinner while [job] runs. Packing a month of photos takes a moment.
Future<T> withBusy<T>(BuildContext context, String message, Future<T> Function() job) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) => PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 16),
              Flexible(child: Text(message)),
            ],
          ),
        ),
      ),
    ),
  );
  // Let the spinner draw before the work starts.
  await Future<void>.delayed(const Duration(milliseconds: 80));
  try {
    return await job();
  } finally {
    nav.pop();
  }
}

/// The message that goes with the file in WhatsApp or email.
String reportShareText(ReportPackage p) {
  final st = statusOf(p);
  final b = StringBuffer()
    ..writeln('Vehicle log, ${fmtMonthLong(p.month)}: ${p.staff.name}')
    ..writeln('${fmtKm(p.summary.km)} km, ${stageLabel(st)}.');
  final last = st.last;
  if (last != null && last.step != 'submit') {
    b.writeln('${signoffVerb(last)} by ${last.name} (${stepRoleLabel(last.step)}).');
  }
  b.writeln();
  switch (st.stage) {
    case ReportStage.approved:
      b.write('Approved. Open the file in Vehicle Log Book (Report tab, Open a signed file) to see the sign-offs.');
      break;
    case ReportStage.returned:
      b.write('Sent back. Open the file in Vehicle Log Book to read the note.');
      break;
    default:
      b.write('Open the file in Vehicle Log Book (Review tab, Open a report file), check it and sign.');
  }
  return b.toString();
}

/// Opens the phone's share sheet with the report file, for WhatsApp, email or Drive.
Future<void> shareReport(BuildContext context, ReportPackage p) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  File file;
  try {
    file = await withBusy(context, 'Packing the report and photos', () => state.exportReport(p));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not prepare the file. Try again.')));
    return;
  }
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'application/octet-stream')],
    subject: 'Vehicle log, ${fmtMonthLong(p.month)}: ${p.staff.name}',
    text: reportShareText(p),
  );
}

/// Picks a report file, checks it and opens it. Reviewers go straight to the report; the staff
/// member whose report it is sees where it stands.
Future<void> openReportFile(BuildContext context) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);

  FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not open the file chooser.')));
    return;
  }
  if (picked == null || picked.files.isEmpty) return;
  final bytes = picked.files.single.bytes;
  if (bytes == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not read that file.')));
    return;
  }
  if (!context.mounted) return;
  final outcome = await withBusy(context, 'Checking the report', () => state.importReport(bytes));
  if (!context.mounted) return;
  await showImportOutcome(context, outcome, state, nav, messenger);
}

/// Tells the person what happened to the file they opened, and opens the report if it was kept.
Future<void> showImportOutcome(
  BuildContext context,
  ImportOutcome outcome,
  AppState state,
  NavigatorState nav,
  ScaffoldMessengerState messenger,
) async {
  final report = outcome.report;
  switch (outcome.kind) {
    case ImportKind.added:
    case ImportKind.updated:
    case ImportKind.alreadyHave:
      if (report == null) return;
      final mine = report.staff.id == state.profile?.id;
      if (!mine) {
        await nav.push(MaterialPageRoute<void>(builder: (_) => ReportReviewScreen(reportKey: report.key)));
        return;
      }
      final last = statusOf(report).last;
      final text = outcome.kind == ImportKind.alreadyHave
          ? 'You already have this version or a newer one.'
          : (last == null ? 'Report updated.' : '${signoffVerb(last)} by ${last.name}. Your report is updated.');
      messenger.showSnackBar(SnackBar(content: Text(text)));
      return;
    case ImportKind.rejected:
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(AppIcons.sealBad, color: Theme.of(ctx).colorScheme.error),
          title: const Text('This file did not pass the checks'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'It was not kept. Ask ${report?.staff.name ?? 'the sender'} to send the report again from their phone.',
                ),
                const SizedBox(height: 12),
                if (outcome.check != null) CheckList(check: PackageCheck(outcome.check!.problems)),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    case ImportKind.conflict:
    case ImportKind.notYours:
    case ImportKind.invalid:
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(outcome.kind == ImportKind.conflict
              ? 'Two different signatures'
              : (outcome.kind == ImportKind.notYours ? 'Not your report' : 'Not a report file')),
          content: Text(outcome.message),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
  }
}
