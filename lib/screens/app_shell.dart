import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../ui/format.dart';
import '../ui/widgets.dart';
import 'log_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';
import 'today_screen.dart';

class AppShell extends StatefulWidget {
  /// Tab to open first. Used by tests.
  final int initialTab;
  const AppShell({super.key, this.initialTab = 0});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final overlay = (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: cs.surface,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    );

    if (!state.ready) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: const Scaffold(body: Center(child: LogoMark(size: 72))),
      );
    }
    if (state.profile == null) {
      return AnnotatedRegion<SystemUiOverlayStyle>(value: overlay, child: const SetupScreen());
    }

    final isReviewer = state.profile!.role != 'staff';
    final destinations = <_Dest>[
      _Dest('Today', Icons.speed_outlined, Icons.speed),
      _Dest('Log book', Icons.menu_book_outlined, Icons.menu_book),
      _Dest('Report', Icons.receipt_long_outlined, Icons.receipt_long),
      if (isReviewer) _Dest('Review', Icons.fact_check_outlined, Icons.fact_check),
      _Dest('Settings', Icons.tune_outlined, Icons.tune),
    ];
    final settingsIndex = destinations.length - 1;
    final index = _index.clamp(0, settingsIndex).toInt();

    final pages = <Widget>[
      TodayScreen(onSeeAll: () => setState(() => _index = 1)),
      const LogScreen(),
      const ReportScreen(),
      if (isReviewer) const ReviewScreen(),
      const SettingsScreen(),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(
                office: state.settings.office,
                name: state.profile!.name,
                onAvatar: () => setState(() => _index = settingsIndex),
              ),
              Expanded(child: IndexedStack(index: index, children: pages)),
            ],
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant))),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final d in destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dest {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  const _Dest(this.label, this.icon, this.selectedIcon);
}

class _Header extends StatelessWidget {
  final String office;
  final String name;
  final VoidCallback onAvatar;

  const _Header({required this.office, required this.name, required this.onAvatar});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
      child: Row(
        children: [
          const LogoMark(size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vehicle Log Book', style: tt.titleMedium?.copyWith(height: 1.1), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (office.isNotEmpty)
                  Text(
                    'DSC $office',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Settings',
            child: InkResponse(
              onTap: onAvatar,
              radius: 28,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: CircleAvatar(
                  radius: 19,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    initialsOf(name),
                    style: tt.labelLarge?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reviewer screen. Reviewing submitted reports is not in this version of the app.
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Text('Review', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Surface(
          child: Column(
            children: [
              const EmptyState(
                icon: Icons.fact_check_outlined,
                title: 'Nothing to review here yet',
                body: 'Checking, verifying and approving staff reports is not in this version of the app. '
                    'Your own trips and report work as usual.',
              ),
              const Divider(),
              const SizedBox(height: 16),
              const ApprovalChain(done: 0),
            ],
          ),
        ),
      ],
    );
  }
}
