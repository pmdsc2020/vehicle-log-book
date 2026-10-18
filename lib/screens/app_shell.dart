import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'setup_screen.dart';
import 'today_screen.dart';
import 'log_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (state.profile == null) {
      return const SetupScreen();
    }

    final isReviewer = state.profile!.role != 'staff';
    final pages = <Widget>[
      const TodayScreen(),
      const LogScreen(),
      const ReportScreen(),
      if (isReviewer) const PlaceholderScreen(title: 'Review'),
      const SettingsScreen(),
    ];
    final labels = [
      'Today',
      'Log Book',
      'Report',
      if (isReviewer) 'Review',
      'Settings',
    ];
    final icons = [
      Icons.today,
      Icons.menu_book,
      Icons.description,
      if (isReviewer) Icons.verified,
      Icons.settings,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Log Book'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              label: Text(state.profile!.role.toUpperCase()),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          ),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: List.generate(labels.length, (i) => NavigationDestination(
          icon: Icon(icons[i]),
          label: labels[i],
        )),
      ),
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  final String title;
  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('$title coming soon')));
}
