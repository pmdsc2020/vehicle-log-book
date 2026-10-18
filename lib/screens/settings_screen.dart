import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/profile.dart';
import '../services/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.profile!;
    final s = state.settings;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Your details', style: Theme.of(context).textTheme.titleLarge),
        ListTile(title: Text(p.name), subtitle: Text('${p.role} · ${p.id}')),
        ListTile(title: const Text('Vehicles'), subtitle: Text(p.vehicles.map((v) => v.no).join(', '))),
        const Divider(),
        Text('Office rules', style: Theme.of(context).textTheme.titleLarge),
        ListTile(title: Text('${s.limitKm} km / month'), subtitle: Text('₹${s.rate}/km · ${s.scope}')),
        const Divider(),
        ListTile(
          title: const Text('Erase all data'),
          subtitle: const Text('Removes trips, photos and settings from this phone'),
          trailing: const Icon(Icons.delete_forever, color: Colors.red),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Erase all data?'),
                content: const Text('This cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Erase', style: TextStyle(color: Colors.red))),
                ],
              ),
            );
            if (ok == true && context.mounted) {
              await state.eraseAll();
            }
          },
        ),
        const SizedBox(height: 24),
        const Text('Vehicle Log Book 1.0 · Flutter port of the DSC-VLB web app.', style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
