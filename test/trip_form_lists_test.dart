// The trip form's Project and Type of work lists: choosing works, and new names can be added.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vehicle_log_book/main.dart';
import 'package:vehicle_log_book/models/profile.dart';
import 'package:vehicle_log_book/services/app_state.dart';

Future<AppState> _open(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 2300);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final s = (await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final s = AppState();
    await s.init(photosDir: Directory.systemTemp.createTempSync('vlb_lists'));
    await s.setProfile(Profile(
      id: 'T-1',
      name: 'Test User',
      designation: '',
      block: 'Nandurbar',
      district: 'Nandurbar',
      mobile: '',
      role: 'staff',
      vehicles: [Vehicle(no: 'MH39 AB 1234', type: 'Two-wheeler')],
      created: '2026-10-01T00:00:00Z',
    ));
    return s;
  }))!;
  await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
    value: s,
    child: const VehicleLogApp(themeMode: ThemeMode.light, splash: false),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start a trip'));
  await tester.pumpAndSettle();
  return s;
}

Future<void> _choose(WidgetTester tester, String current, String next) async {
  await tester.tap(find.text(current).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(next).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('project and type of work can be chosen', (tester) async {
    await _open(tester);
    await _choose(tester, 'ABF (Axis Bank Foundation)', 'NABARD');
    expect(find.text('NABARD'), findsOneWidget);
    expect(find.text('ABF (Axis Bank Foundation)'), findsNothing);

    await _choose(tester, 'Village meeting', 'Survey / planning');
    expect(find.text('Survey / planning'), findsOneWidget);
    expect(find.text('Village meeting'), findsNothing);
  });

  testWidgets('a new project and type of work can be added and are chosen', (tester) async {
    final s = await _open(tester);

    await _choose(tester, 'ABF (Axis Bank Foundation)', 'Add a new project');
    await tester.enterText(find.byType(TextField).last, 'Tata Trusts');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Tata Trusts'), findsOneWidget);
    expect(s.settings.projects, contains('Tata Trusts'));

    await _choose(tester, 'Village meeting', 'Add a new type of work');
    await tester.enterText(find.byType(TextField).last, 'Field visit');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Field visit'), findsOneWidget);
    expect(s.settings.activities, contains('Field visit'));
  });

  testWidgets('cancelling an add keeps the earlier choice', (tester) async {
    final s = await _open(tester);
    final before = s.settings.projects.length;
    await _choose(tester, 'ABF (Axis Bank Foundation)', 'Add a new project');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('ABF (Axis Bank Foundation)'), findsOneWidget);
    expect(find.text('Add a new project'), findsNothing);
    expect(s.settings.projects.length, before);
  });
}
