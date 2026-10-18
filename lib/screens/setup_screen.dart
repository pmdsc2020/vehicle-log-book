import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/profile.dart';
import '../services/app_state.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _id = TextEditingController();
  final _desig = TextEditingController();
  final _block = TextEditingController();
  final _dist = TextEditingController();
  final _mob = TextEditingController();
  final _veh = TextEditingController();
  String _role = 'staff';
  String _vtype = 'Two-wheeler';

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    _desig.dispose();
    _block.dispose();
    _dist.dispose();
    _mob.dispose();
    _veh.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final state = context.read<AppState>();
    final vehNo = _veh.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), ' ').trim();
    final profile = Profile(
      id: _id.text.trim().replaceAll(RegExp(r'\s+'), '-'),
      name: _name.text.trim(),
      designation: _desig.text.trim(),
      block: _block.text.trim(),
      district: _dist.text.trim().isEmpty ? state.settings.office : _dist.text.trim(),
      mobile: _mob.text.trim(),
      role: _role,
      vehicles: vehNo.isEmpty ? [] : [Vehicle(no: vehNo, type: _vtype)],
      created: DateTime.now().toIso8601String(),
    );
    await state.setProfile(profile);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Welcome, ${profile.name.split(' ').first}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppState>().settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Set up this phone')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(settings.org, style: Theme.of(context).textTheme.titleMedium),
            Text(settings.office, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            const Text('Vehicle Log Book', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Log every official trip with photos of the odometer. Each entry locks when you save it.'),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name *', border: OutlineInputBorder()),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _id,
              decoration: const InputDecoration(labelText: 'Staff code *', border: OutlineInputBorder(), helperText: 'Cannot be changed later'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _desig, decoration: const InputDecoration(labelText: 'Designation', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextFormField(controller: _block, decoration: const InputDecoration(labelText: 'Block', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextFormField(controller: _dist, decoration: InputDecoration(labelText: 'District', border: const OutlineInputBorder(), hintText: settings.office)),
            const SizedBox(height: 12),
            TextFormField(controller: _mob, decoration: const InputDecoration(labelText: 'Mobile', border: OutlineInputBorder()), keyboardType: TextInputType.phone),
            const SizedBox(height: 16),
            const Text('Your role in approvals'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'staff', label: Text('Field staff')),
                ButtonSegment(value: 'bi', label: Text('Block Integrator')),
                ButtonSegment(value: 'acc', label: Text('Accountant')),
                ButtonSegment(value: 'di', label: Text('District Integrator')),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _veh,
              decoration: const InputDecoration(labelText: 'Vehicle number', border: OutlineInputBorder(), hintText: 'MH39 AB 1234'),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _vtype,
              decoration: const InputDecoration(labelText: 'Vehicle type', border: OutlineInputBorder()),
              items: const ['Two-wheeler', 'Four-wheeler', 'Other'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() => _vtype = v ?? _vtype),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Padding(padding: EdgeInsets.all(12), child: Text('Save and start', style: TextStyle(fontSize: 16))),
            ),
          ],
        ),
      ),
    );
  }
}
