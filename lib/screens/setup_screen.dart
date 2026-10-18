import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../services/app_state.dart';
import '../ui/widgets.dart';

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

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'This is needed' : null;

  Widget _gap() => const SizedBox(height: 12);

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppState>().settings;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              Row(
                children: [
                  const LogoMark(size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vehicle Log Book', style: tt.titleLarge),
                        Text(
                          '${settings.org}, ${settings.office}',
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text('Set up this phone', style: tt.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Log every official trip with a photo of the meter. Each entry locks when you save it, '
                'so the log book can be trusted.',
                style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Text('About you', style: tt.titleMedium),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name'),
                textCapitalization: TextCapitalization.words,
                validator: _required,
              ),
              _gap(),
              TextFormField(
                controller: _id,
                decoration: const InputDecoration(labelText: 'Staff code', helperText: 'You cannot change this later'),
                validator: _required,
              ),
              _gap(),
              TextFormField(
                controller: _desig,
                decoration: const InputDecoration(labelText: 'Designation'),
                textCapitalization: TextCapitalization.words,
              ),
              _gap(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _block,
                      decoration: const InputDecoration(labelText: 'Block'),
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _dist,
                      decoration: InputDecoration(labelText: 'District', hintText: settings.office),
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ],
              ),
              _gap(),
              TextFormField(
                controller: _mob,
                decoration: const InputDecoration(labelText: 'Mobile'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 24),
              Text('Your part in approvals', style: tt.titleMedium),
              const SizedBox(height: 12),
              _RoleTile(
                selected: _role == 'staff',
                title: 'Field staff',
                body: 'Log trips and send the monthly report',
                onTap: () => setState(() => _role = 'staff'),
              ),
              _RoleTile(
                selected: _role == 'bi',
                title: 'Block Integrator',
                body: 'Check reports from field staff',
                onTap: () => setState(() => _role = 'bi'),
              ),
              _RoleTile(
                selected: _role == 'acc',
                title: 'Accountant',
                body: 'Verify the checked reports',
                onTap: () => setState(() => _role = 'acc'),
              ),
              _RoleTile(
                selected: _role == 'di',
                title: 'District Integrator',
                body: 'Approve reports and use above the limit',
                onTap: () => setState(() => _role = 'di'),
              ),
              const SizedBox(height: 24),
              Text('Your vehicle', style: tt.titleMedium),
              const SizedBox(height: 12),
              TextFormField(
                controller: _veh,
                decoration: const InputDecoration(labelText: 'Vehicle number', hintText: 'MH39 AB 1234'),
                textCapitalization: TextCapitalization.characters,
              ),
              _gap(),
              DropdownButtonFormField<String>(
                value: _vtype,
                decoration: const InputDecoration(labelText: 'Vehicle type'),
                items: const ['Two-wheeler', 'Four-wheeler', 'Other']
                    .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _vtype = v ?? _vtype),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: FilledButton(onPressed: _save, child: const Text('Save and start')),
          ),
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _RoleTile({required this.selected, required this.title, required this.body, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        button: true,
        child: Material(
          color: selected ? cs.primaryContainer.withAlpha(140) : cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: tt.titleSmall),
                        const SizedBox(height: 2),
                        Text(body, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    color: selected ? cs.primary : cs.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
