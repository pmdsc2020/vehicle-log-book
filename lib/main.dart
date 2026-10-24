import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/app_shell.dart';
import 'screens/splash_screen.dart';
import 'services/app_state.dart';
import 'ui/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init();
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const VehicleLogApp(),
    ),
  );
}

class VehicleLogApp extends StatelessWidget {
  /// Tests pass a fixed mode. In the app it follows the choice saved in Settings.
  final ThemeMode? themeMode;

  /// Play the opening logo animation first. Tests turn it off.
  final bool splash;

  const VehicleLogApp({super.key, this.themeMode, this.splash = true});

  @override
  Widget build(BuildContext context) {
    final mode = themeMode ?? context.watch<AppState>().themeMode;
    return MaterialApp(
      title: 'Vehicle Log Book',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      home: splash ? const _Intro() : const AppShell(),
    );
  }
}

/// The logo animation, then the app fading up from behind it.
class _Intro extends StatefulWidget {
  const _Intro();

  @override
  State<_Intro> createState() => _IntroState();
}

class _IntroState extends State<_Intro> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 650),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1).animate(anim), child: child),
      ),
      child: _done
          ? const AppShell(key: ValueKey('app'))
          : SplashScreen(key: const ValueKey('splash'), onDone: () => setState(() => _done = true)),
    );
  }
}
