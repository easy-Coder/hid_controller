import 'package:controller_lab/controller/controller_store.dart';
import 'package:controller_lab/controller/models.dart';
import 'package:controller_lab/ui/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class PermissionStore extends ControllerStore {
  PermissionStore() : super(persistSettings: false) {
    initialized = true;
    selected = const HidDevice(
      id: 1,
      name: 'Pro Controller',
      transport: 'USB',
      vendor: 0x057e,
      product: 0x2009,
      inputCount: 0,
    );
    devices = [selected!];
  }
  bool granted = false;
  int checks = 0;
  @override
  void refreshAccessibility() {
    checks++;
    trusted = granted;
    notifyListeners();
  }
}

void main() {
  testWidgets('returning from settings rechecks without enabling output', (
    tester,
  ) async {
    final store = PermissionStore();
    await tester.pumpWidget(MaterialApp(home: Dashboard(store: store)));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    store.granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(store.checks, 1);
    expect(store.trusted, isTrue);
    expect(store.enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('manual recheck removes the grant prompt when authorized', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1120, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PermissionStore();
    await tester.pumpWidget(MaterialApp(home: Dashboard(store: store)));
    await tester.tap(find.text('Key mappings'));
    await tester.pump();
    expect(find.text('Grant Accessibility access'), findsOneWidget);
    store.granted = true;
    await tester.tap(find.text('Check permission again'));
    await tester.pump();
    expect(store.checks, 1);
    expect(find.text('Grant Accessibility access'), findsNothing);
    expect(store.enabled, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
