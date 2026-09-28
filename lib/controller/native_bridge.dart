import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'models.dart';

final class NativeDevice extends Struct {
  @Uint64()
  external int id;
  @Uint32()
  external int vendor;
  @Uint32()
  external int product;
  @Uint32()
  external int inputCount;
  @Uint32()
  external int reserved;
  @Array(128)
  external Array<Uint8> name;
  @Array(32)
  external Array<Uint8> transport;
}

final class NativeInput extends Struct {
  @Uint32()
  external int cookie;
  @Uint32()
  external int page;
  @Uint32()
  external int usage;
  @Uint32()
  external int kind;
  @Int64()
  external int value;
  @Int64()
  external int minimum;
  @Int64()
  external int maximum;
  @Uint64()
  external int changes;
  @Uint64()
  external int presses;
  @Int64()
  external int seenMinimum;
  @Int64()
  external int seenMaximum;
}

class NativeBridge {
  NativeBridge() {
    if (!Platform.isMacOS) {
      throw UnsupportedError('Controller Lab requires macOS.');
    }
    final bundle = File(Platform.resolvedExecutable).parent.parent.path;
    final lib = DynamicLibrary.open(
      '$bundle/Frameworks/libcontroller_hid.dylib',
    );
    final version = lib.lookupFunction<Uint32 Function(), int Function()>(
      'hc_abi_version',
    );
    if (version() != 2) {
      throw StateError('Incompatible native bridge. Rebuild the app.');
    }
    _start = lib.lookupFunction<Int32 Function(), int Function()>('hc_start');
    _stop = lib.lookupFunction<Void Function(), void Function()>('hc_stop');
    _resetExtrema = lib
        .lookupFunction<Int32 Function(Uint64), int Function(int)>(
          'hc_reset_extrema',
        );
    _usbModeHint = lib.lookupFunction<Int32 Function(), int Function()>(
      'hc_usb_mode_hint',
    );
    _devices = lib
        .lookupFunction<
          Uint32 Function(Pointer<NativeDevice>, Uint32),
          int Function(Pointer<NativeDevice>, int)
        >('hc_devices');
    _inputs = lib
        .lookupFunction<
          Uint32 Function(Uint64, Pointer<NativeInput>, Uint32),
          int Function(int, Pointer<NativeInput>, int)
        >('hc_inputs');
    _map = lib
        .lookupFunction<
          Int32 Function(Uint64, Uint32, Int32),
          int Function(int, int, int)
        >('hc_map');
    _clear = lib.lookupFunction<Void Function(), void Function()>(
      'hc_clear_mappings',
    );
    _enable = lib.lookupFunction<Int32 Function(Int32), int Function(int)>(
      'hc_enable',
    );
    _accessibility = lib
        .lookupFunction<Int32 Function(Int32), int Function(int)>(
          'hc_accessibility',
        );
  }
  late final int Function() _start, _usbModeHint;
  late final int Function(int) _resetExtrema;
  late final void Function() _stop, _clear;
  late final int Function(Pointer<NativeDevice>, int) _devices;
  late final int Function(int, Pointer<NativeInput>, int) _inputs;
  late final int Function(int, int, int) _map;
  late final int Function(int) _enable, _accessibility;
  Pointer<NativeDevice>? _deviceBuffer;
  Pointer<NativeInput>? _inputBuffer;
  bool _started = false;
  void start() {
    final code = _start();
    _started = true;
    if (code != 0) {
      close();
      throw StateError(
        'IOHIDManager could not open (code $code). Check Input Monitoring in System Settings → Privacy & Security, then retry.',
      );
    }
    _deviceBuffer = calloc<NativeDevice>(16);
    _inputBuffer = calloc<NativeInput>(128);
  }

  String _string(Array<Uint8> array, int capacity) => utf8.decode([
    for (var i = 0; i < capacity && array[i] != 0; i++) array[i],
  ], allowMalformed: true);
  List<HidDevice> devices() {
    final buffer = _deviceBuffer!;
    final count = _devices(buffer, 16);
    return [for (var i = 0; i < count; i++) _device(buffer[i])];
  }

  HidDevice _device(NativeDevice d) => HidDevice(
    id: d.id,
    name: _string(d.name, 128).isEmpty
        ? 'HID controller'
        : _string(d.name, 128),
    transport: _string(d.transport, 32),
    vendor: d.vendor,
    product: d.product,
    inputCount: d.inputCount,
    reportId: d.reserved,
  );
  List<HidInput> inputs(int id) {
    final buffer = _inputBuffer!;
    final count = _inputs(id, buffer, 128);
    return [
      for (var i = 0; i < count; i++)
        HidInput(
          cookie: buffer[i].cookie,
          page: buffer[i].page,
          usage: buffer[i].usage,
          kind: buffer[i].kind,
          value: buffer[i].value,
          minimum: buffer[i].minimum,
          maximum: buffer[i].maximum,
          changes: buffer[i].changes,
          presses: buffer[i].presses,
          seenMinimum: buffer[i].seenMinimum,
          seenMaximum: buffer[i].seenMaximum,
        ),
    ];
  }

  bool get trusted => _accessibility(0) == 1;
  void resetExtrema(int id) {
    if (_resetExtrema(id) != 0) {
      throw StateError('Controller disconnected during calibration.');
    }
  }

  bool get usbXinputDetected => _usbModeHint() == 1;
  void requestAccessibility() => _accessibility(1);
  bool enable(bool value) => _enable(value ? 1 : 0) == 0;
  void clearMappings() => _clear();
  void map(int id, int cookie, int key) {
    if (_map(id, cookie, key) != 0) {
      throw StateError('This button is no longer available.');
    }
  }

  void close() {
    if (_started) _stop();
    _started = false;
    if (_deviceBuffer != null) calloc.free(_deviceBuffer!);
    if (_inputBuffer != null) calloc.free(_inputBuffer!);
    _deviceBuffer = null;
    _inputBuffer = null;
  }
}
