import 'dart:ffi' show sizeOf;

import 'package:controller_lab/controller/controller_store.dart';
import 'package:controller_lab/controller/models.dart';
import 'package:controller_lab/controller/native_bridge.dart';
import 'package:controller_lab/ui/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HidInput input({
  int value = 0,
  int min = 0,
  int max = 255,
  int kind = 2,
  int usage = 0x30,
}) => HidInput(
  cookie: 1,
  page: 1,
  usage: usage,
  kind: kind,
  value: value,
  minimum: min,
  maximum: max,
  changes: 0,
);

void main() {
  test('Dart FFI layouts match the native ABI', () {
    expect(sizeOf<NativeDevice>(), 184);
    expect(sizeOf<NativeInput>(), 72);
  });
  test(
    'normalization supports signed ranges, clipping and zero-width ranges',
    () {
      expect(
        input(value: 0, min: -32768, max: 32767).centered,
        closeTo(0, 0.0001),
      );
      expect(input(value: 300).fraction, 1);
      expect(input(value: -10).fraction, 0);
      expect(input(min: 0, max: 0).fraction, 0);
    },
  );
  test(
    'hat switches support four/eight positions and neutral sentinel values',
    () {
      expect(
        input(kind: 3, usage: 0x39, min: 1, max: 8, value: 1).hatLabel,
        'Up',
      );
      expect(
        input(kind: 3, usage: 0x39, min: 1, max: 8, value: 0).hatLabel,
        'Neutral',
      );
      expect(
        input(kind: 3, usage: 0x39, min: 0, max: 7, value: 8).hatLabel,
        'Neutral',
      );
      expect(
        input(kind: 3, usage: 0x39, min: 0, max: 3, value: 1).hatLabel,
        'Right',
      );
    },
  );
  for (final width in [640.0, 1120.0]) {
    testWidgets('empty state fits a $width pixel window', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = ControllerStore(persistSettings: false)..initialized = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Dashboard(store: store),
        ),
      );
      expect(find.text('Ready when you are.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }
  testWidgets('connected tester and mapping screen show actual HID controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1120, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const device = HidDevice(
      id: 1,
      name: 'Nova Lite',
      transport: 'Bluetooth',
      vendor: 1,
      product: 2,
      inputCount: 3,
    );
    final store = ControllerStore(persistSettings: false)
      ..initialized = true
      ..selected = device
      ..devices = [device]
      ..inputs = [
        input(),
        input(usage: 0x31),
        input(kind: 1, usage: 1, value: 1),
      ];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Dashboard(store: store),
      ),
    );
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('X axis'), findsOneWidget);
    await tester.tap(find.text('Key mappings'));
    await tester.pump();
    expect(find.text('Button 1'), findsOneWidget);
    expect(find.text('Grant Accessibility access'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Raw HID data'));
    await tester.pump();
    expect(find.text('Page / Usage'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
  testWidgets(
    'Xbox USB identity shows mode-switch guidance, not controller mappings',
    (tester) async {
      tester.view.physicalSize = const Size(640, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = ControllerStore(persistSettings: false)
        ..initialized = true
        ..usbXinputDetected = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Dashboard(store: store),
        ),
      );
      expect(find.text('USB controller found'), findsOneWidget);
      expect(find.textContaining('View + Menu'), findsOneWidget);
      expect(find.text('Ready when you are.'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
