import 'package:controller_lab/controller/controller_store.dart';
import 'package:controller_lab/controller/models.dart';
import 'package:flutter_test/flutter_test.dart';

const device = HidDevice(
  id: 1,
  name: 'Pro Controller',
  transport: 'USB',
  vendor: 0x57e,
  product: 0x2009,
  inputCount: 19,
);
HidInput button(int usage, {int presses = 0, int value = 0}) => HidInput(
  cookie: 0x53570003 + usage,
  page: 9,
  usage: usage,
  kind: 1,
  value: value,
  minimum: 0,
  maximum: 1,
  changes: presses * 2,
  presses: presses,
);
List<HidInput> axes({int value = 2048, int? minSeen, int? maxSeen}) => [
  for (final e in [0x30, 0x31, 0x32, 0x35].indexed)
    HidInput(
      cookie: 0x53570000 + e.$1,
      page: 1,
      usage: e.$2,
      kind: 2,
      value: value,
      minimum: 0,
      maximum: 4095,
      changes: 0,
      seenMinimum: minSeen,
      seenMaximum: maxSeen,
    ),
];
ControllerStore storeWith(List<HidInput> inputs) =>
    ControllerStore(persistSettings: false)
      ..selected = device
      ..inputs = inputs;
void center(ControllerStore store) {
  store.startCalibration();
  store.captureCenter();
  for (var i = 0; i < 30; i++) {
    store.acceptInputs(axes());
  }
}

void main() {
  test(
    'identify catches a complete tap between UI polls and does not reuse it',
    () {
      final store = storeWith([button(1)]);
      store.identify('A');
      // Latest state is released, but a native press occurred since arming.
      store.acceptInputs([button(1, presses: 1)]);
      expect(store.labelFor(store.inputs.single), 'A');
      expect(store.identifyingControl, isNull);
      expect(store.identificationMessage, contains('Identified A'));
      store.identify('B');
      store.acceptInputs([button(1, presses: 1)]);
      expect(store.identifyingControl, 'B');
      store.acceptInputs([button(1, presses: 2)]);
      expect(store.labelFor(store.inputs.single), 'B');
      store.dispose();
    },
  );
  test(
    'held buttons and simultaneous presses do not select the wrong control',
    () {
      final store = storeWith([button(1, presses: 1, value: 1), button(2)]);
      store.identify('X');
      store.acceptInputs([button(1, presses: 1, value: 1), button(2)]);
      expect(store.identifyingControl, 'X');
      store.acceptInputs([button(1, presses: 2), button(2, presses: 1)]);
      expect(store.identifyingControl, 'X');
      expect(store.identificationMessage, contains('More than one'));
      store.acceptInputs([button(1, presses: 2), button(2, presses: 2)]);
      expect(store.labelFor(store.inputs[1]), 'X');
      expect(store.labelFor(store.inputs[0]), 'South button');
      store.dispose();
    },
  );
  test(
    'stable center and native extrema calibrate travel missed by UI polls',
    () {
      final store = storeWith(axes());
      center(store);
      expect(store.samplingCenter, false);
      expect(store.capturingRange, true);
      // Every latest axis is at rest; full travel happened between snapshots.
      store.acceptInputs(axes(minSeen: 300, maxSeen: 3800));
      expect(store.saveCalibration(), true);
      expect(store.calibrated, true);
      for (final i in store.inputs) {
        expect(store.calibrationFor(i)!.minimum, 300);
        expect(store.calibrationFor(i)!.center, 2048);
        expect(store.normalized(i), 0);
      }
      store.dispose();
    },
  );
  test('center motion is rejected even when the latest frame is at rest', () {
    final store = storeWith(axes());
    store.startCalibration();
    store.captureCenter();
    for (var i = 0; i < 30; i++) {
      store.acceptInputs(axes(minSeen: 1500, maxSeen: 2500));
    }
    expect(store.capturingRange, false);
    expect(store.awaitingCenter, true);
    expect(store.calibrationMessage, contains('sticks moved'));
    store.dispose();
  });
  test(
    'small movements and tilted sticks cannot save a misleading calibration',
    () {
      final store = storeWith(axes());
      center(store);
      store.acceptInputs(axes(minSeen: 2000, maxSeen: 2100));
      expect(store.saveCalibration(), false);
      store.acceptInputs(axes(value: 3500, minSeen: 300, maxSeen: 3800));
      expect(store.saveCalibration(), false);
      expect(store.calibrationMessage, contains('Release both sticks'));
      store.acceptInputs(axes(minSeen: 300, maxSeen: 3800));
      expect(store.saveCalibration(), true);
      store.dispose();
    },
  );
  test('old descriptor calibration and labels do not leak into decoded input fields', () {
    final store = storeWith(axes());
    store.settings['calibration'] = {
      '1:48:37': {'min': 0, 'center': 4864, 'max': 65535},
    };
    store.settings['labels'] = {'9:1:19': 'Incorrect old A'};
    expect(store.calibrated, false);
    expect(store.labelFor(button(1)), 'South button');
    store.dispose();
  });
}
