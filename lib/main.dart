import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/app_shell.dart';
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

  const VehicleLogApp({super.key, this.themeMode});

  @override
  Widget build(BuildContext context) {
    final mode = themeMode ?? context.watch<AppState>().themeMode;
    return MaterialApp(
      title: 'Vehicle Log Book',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      home: const AppShell(),
    );
  }
}
