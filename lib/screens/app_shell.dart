import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../ui/format.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final overlay = (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
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
      const _Dest('Today', AppIcons.today),
      const _Dest('Log book', AppIcons.log),
      const _Dest('Report', AppIcons.report),
      if (isReviewer) const _Dest('Review', AppIcons.review),
      const _Dest('Settings', AppIcons.settings),
    ];
    final settingsIndex = destinations.length - 1;
    final index = _index.clamp(0, settingsIndex).toInt();

    final pages = <Widget>[
      TodayScreen(onSeeAll: () => setState(() => _index = 1), onReport: () => setState(() => _index = 2)),
      const LogScreen(),
      const ReportScreen(),
      if (isReviewer) const ReviewScreen(),
      const SettingsScreen(),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: AuroraBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _Header(
                  office: state.settings.office,
                  name: state.profile!.name,
                  dark: dark,
                  onTheme: () => state.setThemeMode(dark ? 'light' : 'dark'),
                  onAvatar: () => setState(() => _index = settingsIndex),
                ),
                Expanded(
                  child: IndexedStack(
                    index: index,
                    children: [for (var i = 0; i < pages.length; i++) _TabPage(active: i == index, child: pages[i])],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: GlassBar(
                child: NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: (i) {
                    HapticFeedback.selectionClick();
                    setState(() => _index = i);
                  },
                  destinations: [
                    for (final d in destinations)
                      NavigationDestination(
                        icon: Icon(d.icon),
                        selectedIcon: _PoppingIcon(d.icon),
                        label: d.label,
                        tooltip: d.label,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tab that fades and rises a little each time it is brought to the front.
/// The tabs stay alive underneath, so each keeps its month and scroll position.
class _TabPage extends StatefulWidget {
  final bool active;
  final Widget child;
  const _TabPage({required this.active, required this.child});

  @override
  State<_TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<_TabPage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.medium, value: 1);

  @override
  void didUpdateWidget(_TabPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !Motion.reduced(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final v = Motion.emphasized.transform(_c.value);
          return Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child));
        },
      );
}

/// The selected tab's icon springs in.
class _PoppingIcon extends StatelessWidget {
  final IconData icon;
  const _PoppingIcon(this.icon);

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return Icon(icon);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Motion.slow,
      builder: (context, v, child) => Transform.scale(scale: 0.7 + 0.3 * Curves.elasticOut.transform(v), child: child),
      child: Icon(icon),
    );
  }
}

class _Dest {
  final String label;
  final IconData icon;
  const _Dest(this.label, this.icon);
}

class _Header extends StatelessWidget {
  final String office;
  final String name;
  final bool dark;
  final VoidCallback onTheme;
  final VoidCallback onAvatar;

  const _Header({
    required this.office,
    required this.name,
    required this.dark,
    required this.onTheme,
    required this.onAvatar,
  });

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
          ThemeToggle(dark: dark, onPressed: onTheme),
          const SizedBox(width: 4),
          Pressable(
            onTap: onAvatar,
            semanticLabel: 'Settings',
            borderRadius: BorderRadius.circular(30),
            pressedScale: 0.9,
            hoverLift: 2,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: AppGradients.brand(cs.brightness),
                  ),
                  border: Border.all(color: GlassColors.of(context).stroke, width: 2),
                ),
                child: Text(
                  initialsOf(name),
                  style: tt.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
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
      padding: pagePadding(context),
      children: [
        Text('Review', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Surface(
          child: Column(
            children: [
              const EmptyState(
                icon: AppIcons.review,
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
