import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../models/trip.dart';
import '../services/app_state.dart';
import '../services/trip_rules.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// One odometer photo that has been taken but not saved yet.
class _Shot {
  final String key;
  final String hash;
  final String time; // ISO time the photo was taken
  final Uint8List bytes;
  const _Shot({required this.key, required this.hash, required this.time, required this.bytes});
}

/// Start a trip, end an open trip, or log a finished trip.
/// Every reading needs an odometer photo. Saving locks the entry.
class TripFormScreen extends StatefulWidget {
  final String mode; // start | end | full
  final Trip? trip; // the open trip, when mode == 'end'

  const TripFormScreen({super.key, required this.mode, this.trip});

  @override
  State<TripFormScreen> createState() => _TripFormScreenState();
}

class _TripFormScreenState extends State<TripFormScreen> {
  late final AppState _state;

  final _from = TextEditingController();
  final _to = TextEditingController();
  final _task = TextEditingController();
  final _okm = TextEditingController();
  final _ckm = TextEditingController();
  final _returnTo = TextEditingController();
  final _remarks = TextEditingController();
  final _lateReason = TextEditingController();
  final _resetReason = TextEditingController();
  final _priorBy = TextEditingController();
  final _priorRef = TextEditingController();
  final _vehNew = TextEditingController();

  String? _project;
  String? _vehicle;
  String _activity = '';
  String _vtypeNew = 'Two-wheeler';
  String _date = todayStr();
  TimeOfDay _tStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _tEnd = const TimeOfDay(hour: 17, minute: 0);
  bool _reset = false;
  bool _priorNone = false;
  String _priorMode = priorModes.first;
  String _priorDate = todayStr();
  _Shot? _ophoto;
  _Shot? _cphoto;
  bool _busy = false;
  bool _saving = false;
  Map<String, String> _errs = <String, String>{};

  String get _mode => widget.mode;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    final st = _state.settings;
    final p = _state.profile!;
    if (_mode == 'end') {
      _returnTo.text = widget.trip!.from;
    } else {
      final lastProject = _state.meta['lastProject'] as String?;
      if (lastProject != null && st.projects.contains(lastProject)) {
        _project = lastProject;
      } else if (st.projects.isNotEmpty) {
        _project = st.projects.first;
      }
      final nos = p.vehicles.map((v) => v.no).toList();
      final lastVeh = _state.meta['lastVehicle'] as String?;
      if (lastVeh != null && nos.contains(lastVeh)) {
        _vehicle = lastVeh;
      } else if (nos.isNotEmpty) {
        _vehicle = nos.first;
      }
      if (st.activities.isNotEmpty) _activity = st.activities.first;
      final lastFrom = _state.meta['lastFrom'] as String?;
      _from.text = (lastFrom != null && lastFrom.isNotEmpty) ? lastFrom : p.block;
      _priorBy.text = (_state.meta['lastPriorBy'] as String?) ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [
      _from, _to, _task, _okm, _ckm, _returnTo, _remarks,
      _lateReason, _resetReason, _priorBy, _priorRef, _vehNew,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------ derived values

  bool get _hasVehicles => _state.profile!.vehicles.isNotEmpty;

  String get _vehicleNo {
    if (_mode == 'end') return widget.trip!.vehicle;
    if (_hasVehicles) return _vehicle ?? '';
    return _vehNew.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), ' ').trim();
  }

  String get _projectName => _mode == 'end' ? widget.trip!.project : (_project ?? '');

  String get _tripDate {
    if (_mode == 'full') return _date;
    if (_mode == 'end') return widget.trip!.date;
    return todayStr();
  }

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String get _startAt {
    if (_mode == 'full') return isoAt(_date, _hhmm(_tStart));
    if (_mode == 'end') return widget.trip!.start.at;
    return nowIso();
  }

  int? _num(String s) {
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  int? get _openKm => _mode == 'end' ? widget.trip!.start.km : _num(_okm.text);

  int? get _closeKm => _mode == 'start' ? null : _num(_ckm.text);

  int? get _dist {
    final o = _openKm;
    final c = _closeKm;
    if (o == null || c == null || c <= o) return null;
    return c - o;
  }

  bool get _needPrior {
    if (_mode == 'end' && widget.trip!.prior != null) return false;
    final used = usedKm(_state.trips, _state.settings, monthOf(_tripDate), _projectName,
        _mode == 'end' ? widget.trip!.id : null);
    final lim = _state.settings.limitKm;
    final thisKm = _dist ?? 0;
    return used >= lim || (thisKm > 0 && used + thisKm > lim);
  }

  bool _isOld(_Shot s) {
    if (_mode == 'full') return localDateOf(s.time) != _date;
    final age = DateTime.now().difference(DateTime.parse(s.time)).inMinutes;
    return age > _state.settings.photoMaxAge;
  }

  // ------------------------------------------------------------ actions

  Future<void> _pickPhoto(bool opening, ImageSource source) async {
    setState(() => _busy = true);
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 62,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      DateTime when;
      try {
        when = await x.lastModified();
      } catch (_) {
        when = DateTime.now();
      }
      final shot = _Shot(
        key: uid('P'),
        hash: sha256.convert(bytes).toString(),
        time: DateTime.fromMillisecondsSinceEpoch(when.millisecondsSinceEpoch, isUtc: true)
            .toIso8601String(),
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() {
        if (opening) {
          _ophoto = shot;
          _errs.remove('ophoto');
        } else {
          _cphoto = shot;
          _errs.remove('cphoto');
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the photo. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final today = todayStr();
    final lateDays = _state.settings.lateDays < 0 ? 0 : _state.settings.lateDays;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_date),
      firstDate: DateTime.parse(addDays(today, -lateDays)),
      lastDate: DateTime.parse(today),
    );
    if (picked != null) {
      setState(() {
        _date = dateStr(picked);
        _errs.remove('date');
      });
    }
  }

  Future<void> _pickPriorDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_priorDate),
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _priorDate = dateStr(picked));
  }

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(context: context, initialTime: start ? _tStart : _tEnd);
    if (picked != null) {
      setState(() {
        if (start) {
          _tStart = picked;
        } else {
          _tEnd = picked;
        }
        _errs.remove('tend');
      });
    }
  }

  Future<void> _submit() async {
    final st = _state.settings;
    final isEnd = _mode == 'end';
    final trip = widget.trip;
    final errs = <String, String>{};
    final today = todayStr();

    final project = _projectName;
    final vehicle = _vehicleNo;
    final from = isEnd ? trip!.from : _from.text.trim();
    final to = isEnd ? trip!.to : _to.text.trim();
    final task = isEnd ? trip!.task : _task.text.trim();
    final date = _tripDate;
    final startAt = _startAt;
    final endAt = _mode == 'full' ? isoAt(_date, _hhmm(_tEnd)) : nowIso();
    final okm = _openKm;
    final ckm = _closeKm;

    if (!isEnd) {
      if (project.isEmpty) errs['project'] = 'Choose the project.';
      if (vehicle.isEmpty) errs['vehicle'] = 'Enter the vehicle number.';
      if (from.isEmpty) errs['from'] = 'Where did the trip start?';
      if (to.isEmpty) errs['to'] = 'Which village did you go to?';
      if (task.length < 3) errs['task'] = 'Write the work done on this trip.';
      if (_ophoto == null) errs['ophoto'] = 'Take a photo of the opening reading.';
    }
    if (_mode != 'start' && _cphoto == null) {
      errs['cphoto'] = 'Take a photo of the closing reading.';
    }

    Map<String, dynamic>? lateInfo;
    if (_mode == 'full') {
      final lateDays = st.lateDays < 0 ? 0 : st.lateDays;
      final oldest = addDays(today, -lateDays);
      if (_date.compareTo(today) > 0) {
        errs['date'] = 'Pick a date up to today.';
      } else if (_date.compareTo(oldest) < 0) {
        errs['date'] = 'Entries older than $lateDays days cannot be added. Speak to your Block Integrator.';
      }
      if (_date.compareTo(today) < 0) {
        final why = _lateReason.text.trim();
        lateInfo = <String, dynamic>{'reason': why};
        if (why.isEmpty) errs['late'] = 'Give the reason for the late entry.';
      }
      if (endAt.compareTo(startAt) <= 0) {
        errs['tend'] = 'Back time must be after the start time.';
      } else if (endAt.compareTo(nowIso()) > 0) {
        errs['tend'] = 'Back time is later than now.';
      }
    }

    if (_mode == 'start' && _state.trips.any((t) => t.status == 'open' && t.vehicle == vehicle)) {
      errs['okm'] = 'A trip on $vehicle is still open. End it first.';
    }

    Map<String, dynamic>? reset;
    if (_reset && !isEnd) {
      final why = _resetReason.text.trim();
      reset = <String, dynamic>{'reason': why};
      if (why.isEmpty) errs['reset'] = 'Give the reason the meter changed.';
    }

    final chk = checkReadings(
      trips: _state.trips,
      vehicle: vehicle,
      date: date,
      atIso: startAt,
      open: okm,
      close: _mode == 'start' ? null : ckm,
      excludeId: trip?.id,
      reset: reset != null,
    );
    final okmErr = chk.errs['okm'];
    if (!isEnd && okmErr != null && !errs.containsKey('okm')) errs['okm'] = okmErr;

    if (_mode != 'start') {
      final o = okm ?? 0;
      final ckmErr = chk.errs['ckm'];
      if (ckm == null) {
        errs['ckm'] = 'Enter the closing reading from the meter.';
      } else if (isEnd && ckm <= o) {
        errs['ckm'] = 'Closing reading must be more than the opening reading ${fmtKm(o)} km.';
      } else if (ckmErr != null) {
        errs['ckm'] = ckmErr;
      } else if (ckm - o > 1500) {
        errs['ckm'] = 'More than 1,500 km in one trip. Check the reading.';
      }
    }

    Map<String, dynamic>? prior;
    if (_needPrior) {
      if (_priorNone) {
        prior = <String, dynamic>{'none': true, 'by': '', 'date': '', 'mode': '', 'ref': ''};
      } else {
        final by = _priorBy.text.trim();
        prior = <String, dynamic>{
          'by': by,
          'mode': _priorMode,
          'date': _priorDate,
          'ref': _priorRef.text.trim(),
          'none': false,
        };
        if (by.isEmpty) errs['pby'] = 'Write who approved, or tick "not taken yet".';
      }
    }

    if (errs.isNotEmpty) {
      setState(() => _errs = errs);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please correct the marked fields.')),
      );
      return;
    }

    // Confirm: after this the entry is locked.
    final dist = _mode == 'start' ? null : (ckm! - okm!);
    final summary = StringBuffer()
      ..writeln('Date: ${fmtDate(date)}${lateInfo != null ? '  (late entry)' : ''}')
      ..writeln('Route: $from to $to')
      ..writeln('Vehicle: $vehicle')
      ..writeln('Opening: ${fmtKm(okm ?? 0)} km');
    if (dist != null) {
      summary
        ..writeln('Closing: ${fmtKm(ckm!)} km')
        ..writeln('Distance: ${fmtKm(dist)} km');
    }
    if (!isEnd && chk.gap > 0) {
      summary.writeln('Not logged: ${fmtKm(chk.gap)} km since the last trip');
    }
    summary
      ..writeln()
      ..write('After locking, readings, photos and details cannot be changed. You can only add a note.');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_mode == 'start' ? 'Lock and start this trip?' : 'Lock this trip?'),
        content: Text(summary.toString()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Check again')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lock and save')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      if (isEnd) {
        final shot = _cphoto!;
        await _state.storage.savePhoto(shot.key, shot.bytes);
        final end = Reading(
          km: ckm!,
          photoKey: shot.key,
          photoHash: shot.hash,
          at: endAt,
          photoTime: shot.time,
          oldPhoto: _isOld(shot),
          returnTo: _returnTo.text.trim(),
          remarks: _remarks.text.trim(),
        );
        await _state.closeTrip(trip!, end, prior: prior);
      } else {
        final profile = _state.profile!;
        var vtype = _vtypeNew;
        if (profile.vehicles.isEmpty) {
          profile.vehicles = [Vehicle(no: vehicle, type: _vtypeNew)];
          await _state.setProfile(profile);
        } else {
          for (final v in profile.vehicles) {
            if (v.no == vehicle) vtype = v.type;
          }
        }

        final o = _ophoto!;
        await _state.storage.savePhoto(o.key, o.bytes);
        final startReading = Reading(
          km: okm!,
          photoKey: o.key,
          photoHash: o.hash,
          at: startAt,
          photoTime: o.time,
          oldPhoto: _isOld(o),
          prevKm: chk.prevKm,
        );

        Reading? endReading;
        int? km;
        var status = 'open';
        if (_mode == 'full') {
          final c = _cphoto!;
          await _state.storage.savePhoto(c.key, c.bytes);
          endReading = Reading(
            km: ckm!,
            photoKey: c.key,
            photoHash: c.hash,
            at: endAt,
            photoTime: c.time,
            oldPhoto: _isOld(c),
            returnTo: _returnTo.text.trim(),
            remarks: _remarks.text.trim(),
          );
          km = ckm - okm;
          status = 'closed';
        }

        final t = Trip(
          id: uid('T'),
          mode: _mode,
          date: date,
          month: monthOf(date),
          project: project,
          vehicle: vehicle,
          vtype: vtype,
          from: from,
          to: to,
          activity: _activity,
          task: task,
          start: startReading,
          end: endReading,
          km: km,
          status: status,
          late: lateInfo,
          meterReset: reset,
          prior: prior,
          notes: <Note>[],
          loggedAt: nowIso(),
        );
        await _state.createTrip(t);
      }

      final choices = <String, dynamic>{};
      if (!isEnd) {
        choices['lastProject'] = project;
        choices['lastVehicle'] = vehicle;
        choices['lastFrom'] = from;
      }
      final approver = prior == null ? '' : (prior['by'] as String? ?? '');
      if (approver.isNotEmpty) choices['lastPriorBy'] = approver;
      if (choices.isNotEmpty) await _state.rememberChoices(choices);

      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(_mode == 'start'
            ? 'Trip started. Opening ${fmtKm(okm ?? 0)} km is locked.'
            : 'Trip saved and locked.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------------------------------------------ widgets

  String _rateStr(double r) => r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(2);

  Widget _section(String title, List<Widget> children, {String? subtitle}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Surface(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: tt.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _field(
    String key,
    String label,
    TextEditingController c, {
    String? hint,
    String? helper,
    int lines = 1,
    bool digits = false,
    bool enabled = true,
    bool big = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        enabled: enabled,
        minLines: lines,
        maxLines: lines,
        keyboardType: digits ? TextInputType.number : TextInputType.text,
        inputFormatters: digits ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly] : null,
        style: big ? numStyle(28, weight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface) : null,
        onChanged: (_) => setState(() => _errs.remove(key)),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 2,
          errorText: _errs[key],
          errorMaxLines: 3,
        ),
      ),
    );
  }

  Widget _dropdown(String key, String label, List<String> items, String? value, ValueChanged<String?> onChanged) {
    final shown = (value != null && items.contains(value)) ? value : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        value: shown,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, errorText: _errs[key], errorMaxLines: 3),
        items: items.map((s) => DropdownMenuItem<String>(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  /// A date or time that opens a picker. Looks like a field, reads like a label and a value.
  Widget _pickTile(String label, String value, IconData icon, VoidCallback? onTap, {String? error}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: error != null ? cs.error : cs.outlineVariant, width: error != null ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        Text(value, style: tt.titleSmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 14),
            child: Text(error, style: tt.bodySmall?.copyWith(color: cs.error)),
          ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _photoBox(String title, _Shot? shot, bool opening) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final err = _errs[opening ? 'ophoto' : 'cphoto'];
    final allowGallery = _mode == 'full';
    final old = shot != null && _isOld(shot);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tt.labelLarge),
          const SizedBox(height: 8),
          if (shot == null)
            Material(
              color: cs.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: err != null ? cs.error : cs.outline.withAlpha(130),
                  width: err != null ? 2 : 1.2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _busy ? null : () => _pickPhoto(opening, ImageSource.camera),
                child: SizedBox(
                  height: 116,
                  width: double.infinity,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_camera_outlined, size: 32, color: cs.primary),
                      const SizedBox(height: 6),
                      Text('Take a photo of the meter', style: tt.labelLarge?.copyWith(color: cs.primary)),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(shot.bytes, height: 180, width: double.infinity, fit: BoxFit.cover),
                ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: StatusPill(
                    old ? 'Not a fresh photo' : 'Photo ready',
                    kind: old ? PillKind.flag : PillKind.locked,
                    icon: old ? Icons.warning_amber_rounded : Icons.check_circle,
                  ),
                ),
              ],
            ),
            if (old)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  allowGallery
                      ? 'Not taken on the trip date. It will be marked for checking.'
                      : 'Older than ${_state.settings.photoMaxAge} minutes. It will be marked for checking.',
                  style: tt.bodySmall?.copyWith(color: cs.error),
                ),
              ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => _pickPhoto(opening, ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Retake'),
                ),
                if (allowGallery)
                  TextButton.icon(
                    onPressed: _busy ? null : () => _pickPhoto(opening, ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
              ],
            ),
          ],
          if (shot == null && allowGallery)
            TextButton.icon(
              onPressed: _busy ? null : () => _pickPhoto(opening, ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose from gallery'),
            ),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(err, style: tt.bodySmall?.copyWith(color: cs.error)),
            ),
        ],
      ),
    );
  }

  Widget _notice(String text, {bool warn = false, IconData icon = Icons.info_outline}) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bg = warn ? cs.tertiaryContainer : cs.surfaceContainer;
    final fg = warn ? cs.onTertiaryContainer : cs.onSurface;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: fg),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: tt.bodyMedium?.copyWith(color: fg))),
        ],
      ),
    );
  }

  Widget _distanceCard(int dist, bool high) {
    final st = _state.settings;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fg = high ? cs.onTertiaryContainer : cs.onPrimaryContainer;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: high ? cs.tertiaryContainer : cs.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmtKm(dist), style: numStyle(40, weight: FontWeight.w700, color: fg)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('km', style: tt.titleMedium?.copyWith(color: fg)),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(fmtRs(dist * st.rate), style: numStyle(26, weight: FontWeight.w700, color: fg)),
                  const SizedBox(height: 3),
                  Text('at ₹${_rateStr(st.rate)} a km', style: tt.bodySmall?.copyWith(color: fg)),
                ],
              ),
            ],
          ),
          if (high) ...[
            const SizedBox(height: 10),
            Text('This is a high km trip. The entry will be marked for checking.', style: tt.bodyMedium?.copyWith(color: fg)),
          ],
        ],
      ),
    );
  }

  Widget _priorBlock() {
    final st = _state.settings;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final used = usedKm(_state.trips, st, monthOf(_tripDate), _projectName,
        _mode == 'end' ? widget.trip!.id : null);
    final thisKm = _dist ?? 0;
    final over = (used + thisKm - st.limitKm) < 0 ? 0 : (used + thisKm - st.limitKm);
    final intro = StringBuffer()
      ..write('${fmtKm(used)} km already used of the ${fmtKm(st.limitKm)} km monthly limit');
    if (thisKm > 0) {
      intro.write('. This trip takes it to ${fmtKm(used + thisKm)} km (${fmtKm(over)} km above)');
    }
    intro.write('. Km above the limit are paid only after District Integrator approval. '
        'Record the approval you took before travelling.');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.tertiary, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.policy_outlined, color: cs.tertiary),
                const SizedBox(width: 10),
                Expanded(child: Text('Above the monthly limit', style: tt.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Text(intro.toString(), style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            _field('pby', 'Approval given by', _priorBy, hint: 'Name of District Integrator', enabled: !_priorNone),
            _dropdown('pmode', 'How', priorModes, _priorMode, (v) {
              if (v != null) setState(() => _priorMode = v);
            }),
            _pickTile('Approval date', fmtDate(_priorDate), Icons.event_outlined, _priorNone ? null : _pickPriorDate),
            _field('pref', 'Reference or remark', _priorRef, hint: 'e.g. WhatsApp message 15-10, 10:05', enabled: !_priorNone),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _priorNone,
              onChanged: (v) => setState(() {
                _priorNone = v ?? false;
                _errs.remove('pby');
              }),
              title: const Text('I have not taken approval yet'),
              subtitle: const Text('The km above the limit will be marked "No prior approval".'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _endSummary() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final trip = widget.trip!;
    final started = DateTime.parse(trip.start.at).toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Surface(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const StatusPill('On a trip', kind: PillKind.open),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Started ${DateFormat('d MMM, h:mm a').format(started).toLowerCase()}',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            RouteLine(from: trip.from, to: trip.to, large: true, toLines: 2),
            const SizedBox(height: 14),
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
            if (trip.task.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(trip.task, style: tt.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = _state.settings;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isEnd = _mode == 'end';
    final isStart = _mode == 'start';
    final isFull = _mode == 'full';
    final title = isStart ? 'Start a trip' : (isEnd ? 'End trip' : 'Log a finished trip');
    final dist = _dist;
    final high = dist != null && dist > st.highKm;

    String lastHint = '';
    if (!isEnd && _vehicleNo.isNotEmpty) {
      final nb = neighbours(_state.trips, _vehicleNo, _tripDate, _startAt, null);
      lastHint = nb.prev == null
          ? 'First trip on this vehicle in this app.'
          : 'Last reading on $_vehicleNo: ${fmtKm(readingOf(nb.prev!))} km (${fmtDate(nb.prev!.date)})';
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (isEnd) _endSummary(),
          if (isFull)
            _section('When', [
              _pickTile('Trip date', fmtDate(_date), Icons.event_outlined, _pickDate, error: _errs['date']),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _pickTile('Left at', _tStart.format(context), Icons.schedule, () => _pickTime(true))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _pickTile('Back at', _tEnd.format(context), Icons.schedule, () => _pickTime(false),
                        error: _errs['tend']),
                  ),
                ],
              ),
              if (_date.compareTo(todayStr()) < 0)
                _field('late', 'Why is this entry late?', _lateReason,
                    hint: 'e.g. No network in the village, phone battery empty'),
            ]),
          if (!isEnd)
            _section('Trip', [
              _dropdown('project', 'Project', st.projects, _project, (v) => setState(() {
                    _project = v;
                    _errs.remove('project');
                  })),
              if (_hasVehicles)
                _dropdown(
                  'vehicle',
                  'Vehicle',
                  _state.profile!.vehicles.map((v) => v.no).toList(),
                  _vehicle,
                  (v) => setState(() {
                    _vehicle = v;
                    _errs.remove('vehicle');
                  }),
                )
              else ...[
                _field('vehicle', 'Vehicle number', _vehNew, hint: 'MH39 AB 1234'),
                _dropdown('vtype', 'Vehicle type', const ['Two-wheeler', 'Four-wheeler', 'Other'], _vtypeNew, (v) {
                  if (v != null) setState(() => _vtypeNew = v);
                }),
              ],
              _field('from', 'From', _from, hint: 'Starting place'),
              _field('to', 'To (village)', _to, hint: 'Separate villages with commas'),
              _dropdown('activity', 'Type of work', st.activities, _activity, (v) {
                if (v != null) setState(() => _activity = v);
              }),
              _field('task', 'Task performed', _task,
                  lines: 2, hint: 'e.g. PIC meeting on net plan; checked farm pond work'),
            ]),
          if (!isEnd)
            _section(
              'Opening reading',
              [
                _field('okm', 'Odometer (km)', _okm, digits: true, big: true, hint: '000000', helper: lastHint),
                _photoBox('Photo of the meter', _ophoto, true),
              ],
            ),
          if (!isStart)
            _section(
              'Closing reading',
              [
                _field('ckm', 'Odometer (km)', _ckm, digits: true, big: true, hint: '000000'),
                _photoBox('Photo of the meter', _cphoto, false),
                _field('return', 'Returned to (optional)', _returnTo),
                _field('remarks', 'Remarks (optional)', _remarks),
              ],
            ),
          if (dist != null) _distanceCard(dist, high),
          if (!isEnd)
            _section('Meter', [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _reset,
                onChanged: (v) => setState(() {
                  _reset = v ?? false;
                  _errs.remove('reset');
                }),
                title: const Text('Meter was reset or replaced'),
                subtitle: const Text('Tick only if the odometer was changed, and give the reason.'),
              ),
              if (_reset)
                _field('reset', 'Reason', _resetReason, hint: 'e.g. Speedometer replaced at garage on 10-10'),
            ]),
          if (_needPrior) _priorBlock(),
          Padding(
            padding: const EdgeInsets.only(bottom: 14, left: 2),
            child: Text(
              isFull
                  ? 'GPS is not recorded for trips logged afterwards.'
                  : 'GPS is not recorded in this version of the app.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          _notice(
            'After locking, readings, photos and details cannot be changed. You can only add a note.',
            warn: true,
            icon: Icons.lock_outline,
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: FilledButton.icon(
              onPressed: (_saving || _busy) ? null : _submit,
              icon: const Icon(Icons.lock_outline),
              label: Text(_saving ? 'Saving' : (isStart ? 'Lock and start' : 'Lock and save')),
            ),
          ),
        ),
      ),
    );
  }
}
