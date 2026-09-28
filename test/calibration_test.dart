import 'package:controller_lab/controller/calibration.dart';
import 'package:controller_lab/controller/controller_store.dart';
import 'package:controller_lab/controller/models.dart';
import 'package:controller_lab/ui/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HidInput axis(int usage, {int cookie = 1, int value = 32768}) => HidInput(
  cookie: cookie,
  page: 1,
  usage: usage,
  kind: 2,
  value: value,
  minimum: 0,
  maximum: 65535,
  changes: 0,
);

void main() {
  testWidgets(
    'stick calibration steps work in a narrow window and reject missing travel',
    (tester) async {
      tester.view.physicalSize = const Size(640, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = ControllerStore(persistSettings: false)
        ..initialized = true
        ..selected = const HidDevice(
          id: 1,
          name: 'Pro Controller',
          transport: 'USB',
          vendor: 0x57e,
          product: 0x2009,
          inputCount: 4,
        )
        ..inputs = [
          axis(0x30, cookie: 1),
          axis(0x31, cookie: 2),
          axis(0x32, cookie: 3),
          axis(0x35, cookie: 4),
        ];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Dashboard(store: store),
        ),
      );
      expect(find.text('LS · Left stick'), findsOneWidget);
      expect(find.text('RS · Right stick'), findsOneWidget);
      await tester.ensureVisible(find.text('Calibrate sticks'));
      await tester.tap(find.text('Calibrate sticks'));
      await tester.pump();
      expect(find.text('Capture center'), findsOneWidget);
      await tester.tap(find.text('Capture center'));
      for (var i = 0; i < 30; i++) {
        store.acceptInputs(store.inputs);
      }
      await tester.pump();
      expect(find.text('Save range'), findsOneWidget);
      await tester.tap(find.text('Save range'));
      await tester.pump();
      expect(find.textContaining('Move every stick axis'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
  test('calibration uses captured center and asymmetric endpoints', () {
    const c = AxisCalibration(100, 400, 1000);
    expect(c.normalize(400), 0);
    expect(c.normalize(100), -1);
    expect(c.normalize(1000), 1);
    expect(c.normalize(250), -0.5);
    expect(c.normalize(700), 0.5);
    expect(c.normalize(2000), 1);
    expect(c.normalize(-100), -1);
    expect(AxisCalibration.fromJson(c.toJson()).normalize(400), 0);
    expect(const AxisCalibration(10, 10, 10).valid, false);
  });
  test('radial dead zone removes resting noise and preserves directions', () {
    expect(applyDeadzone(0.02, -0.01, 0.05), (x: 0.0, y: 0.0));
    expect(applyDeadzone(1, 0, 0.05).x, 1);
    final diagonal = applyDeadzone(1, 1, 0.05);
    expect(diagonal.x, closeTo(0.7071, 0.0001));
    expect(diagonal.y, closeTo(0.7071, 0.0001));
    expect(applyDeadzone(0, -1, 0.05).y, -1);
  });
  test('stick pairing follows usage, independent of descriptor order', () {
    final pairs = findSticks([axis(0x35), axis(0x31), axis(0x32), axis(0x30)]);
    expect(pairs[0].x.usage, 0x30);
    expect(pairs[0].y.usage, 0x31);
    expect(pairs[1].x.usage, 0x32);
    expect(pairs[1].y.usage, 0x35);
    final xbox = findSticks([
      axis(0x32),
      axis(0x35),
      axis(0x34),
      axis(0x33),
      axis(0x30),
      axis(0x31),
    ]);
    expect(xbox[1].x.usage, 0x33);
    expect(xbox[1].y.usage, 0x34);
    expect(findSticks([axis(0x30)]), isEmpty);
  });
  test('center capture cannot save before both directions are exercised', () {
    final store = ControllerStore(persistSettings: false)
      ..selected = const HidDevice(
        id: 1,
        name: 'Pro Controller',
        transport: 'USB',
        vendor: 0x57e,
        product: 0x2009,
        inputCount: 4,
      )
      ..inputs = [
        axis(0x30, cookie: 1),
        axis(0x31, cookie: 2),
        axis(0x32, cookie: 3),
        axis(0x35, cookie: 4),
      ];
    store.startCalibration();
    expect(store.awaitingCenter, true);
    store.captureCenter();
    for (var i = 0; i < 30; i++) {
      store.acceptInputs(store.inputs);
    }
    expect(store.capturingRange, true);
    expect(store.saveCalibration(), false);
    expect(store.calibrated, false);
    store.cancelCalibration();
    expect(store.capturingRange, false);
    store.dispose();
  });
}
