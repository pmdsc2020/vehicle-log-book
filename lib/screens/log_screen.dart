import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  String? _month;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final months = state.trips.map((t) => t.month).toSet().toList()..sort((a, b) => b.compareTo(a));
    if (months.isEmpty) months.add('${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}');
    _month ??= months.first;
    final list = state.tripsOfMonth(_month!);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          value: _month,
          decoration: const InputDecoration(labelText: 'Month', border: OutlineInputBorder()),
          items: months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
          onChanged: (v) => setState(() => _month = v),
        ),
        const SizedBox(height: 16),
        if (list.isEmpty)
          const Center(child: Text('No entries this month'))
        else
          ...list.map((t) => Card(
                child: ListTile(
                  title: Text('${t.from} → ${t.to}'),
                  subtitle: Text('${t.project} · ${t.date} · ${t.status}'),
                  trailing: Text(t.km != null ? '${t.km} km' : 'open'),
                ),
              )),
      ],
    );
  }
}
