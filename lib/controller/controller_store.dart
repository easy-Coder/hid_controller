import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'native_bridge.dart';
import 'calibration.dart';

class ControllerStore extends ChangeNotifier {
  ControllerStore({this.persistSettings = true});
  final bool persistSettings;
  NativeBridge? _bridge;
  Timer? _timer;
  List<HidDevice> devices = [];
  List<HidInput> inputs = [];
  List<String> activity = [];
  HidDevice? selected;
  String? error, profileError;
  bool enabled = false, trusted = false, initialized = false;
  bool usbXinputDetected = false;
  int _ticks = 0;
  bool _disposed = false;
  final Map<String, Map<String, int>> _profiles = {};
  Future<void> _pendingSave = Future.value();
  Future<void> _pendingSettingsSave = Future.value();
  final Map<String, dynamic> _settings = {};
  String? calibrationMessage, identifyingControl;
  bool awaitingCenter = false, capturingRange = false;
  bool samplingCenter = false;
  int _centerSamples = 0;
  final Map<String, double> _centerSums = {};
  final Map<int, int> _identifyBaseline = {};
  String? identificationMessage;
  final Map<String, AxisCalibration> _draft = {};
  Map<String, dynamic> get settings => selected == null
      ? {}
      : (_settings.putIfAbsent(selected!.profileId, () => <String, dynamic>{})
            as Map<String, dynamic>);
  List<StickAxes> get sticks => findSticks(inputs);
  List<HidInput> get stickInputs => [
    for (final stick in sticks) ...[stick.x, stick.y],
  ];
  bool get isSwitchMode =>
      selected?.vendor == 0x057e && selected?.product == 0x2009;
  double get deadzone =>
      ((settings['deadzone'] as num?)?.toDouble() ?? 0.05).clamp(0, 0.5);
  String labelFor(HidInput input) {
    final saved = (settings['labels'] as Map?)?[input.bindingId] as String?;
    if (saved != null) return saved;
    if (isSwitchMode &&
        input.isButton &&
        input.cookie >= 0x53570000 &&
        input.cookie < 0x53570013) {
      return const [
        'South button',
        'East button',
        'West button',
        'North button',
        'LB',
        'RB',
        'LT',
        'RT',
        'View',
        'Menu',
        'LS click',
        'RS click',
        'Home',
        'Capture',
      ][input.usage - 1];
    }
    return input.label;
  }

  AxisCalibration? calibrationFor(HidInput input) {
    final json = (settings['calibration'] as Map?)?[input.bindingId];
    if (json is! Map<String, dynamic>) return null;
    try {
      final calibration = AxisCalibration.fromJson(json);
      return calibration.valid ? calibration : null;
    } catch (_) {
      return null;
    }
  }

  bool get calibrated =>
      stickInputs.isNotEmpty &&
      stickInputs.every((i) => calibrationFor(i) != null);
  double normalized(HidInput input) {
    if (capturingRange && _draft[input.bindingId] != null) {
      final draft = _draft[input.bindingId]!;
      final preview = draft.valid
          ? draft
          : AxisCalibration(
              input.minimum.toDouble(),
              draft.center,
              input.maximum.toDouble(),
            );
      return preview.normalize(input.value);
    }
    return calibrationFor(input)?.normalize(input.value) ?? input.centered;
  }

  ({double x, double y}) reading(StickAxes stick) =>
      applyDeadzone(normalized(stick.x), normalized(stick.y), deadzone);
  File get _settingsFile => File('${_profileFile.parent.path}/controls.json');
  Map<String, int> get mappings {
    final live = {for (final i in inputs.where((i) => i.isButton)) i.bindingId};
    return Map.fromEntries(
      (_profiles[selected?.profileId] ?? {}).entries.where(
        (e) => live.contains(e.key),
      ),
    );
  }

  int keyFor(HidInput input) => mappings[input.bindingId] ?? -1;
  File get _profileFile => File(
    '${Platform.environment['HOME']}/Library/Application Support/Controller Lab/profiles.json',
  );
  Future<void> initialize() async {
    try {
      if (await _profileFile.exists()) {
        final json = jsonDecode(
          await _profileFile.readAsString(),
        ) as Map<String, dynamic>;
        for (final entry in json.entries) {
          _profiles[entry.key] =
              (entry.value as Map<String, dynamic>).map(
                (key, value) => MapEntry(key, value as int),
              )..removeWhere(
                (_, value) => !keyboardKeys.containsKey(value) || value == -1,
              );
        }
      }
    } catch (e) {
      profileError = 'Could not read saved mappings: $e';
    }
    try {
      if (await _settingsFile.exists()) {
        final json = jsonDecode(
          await _settingsFile.readAsString(),
        ) as Map<String, dynamic>;
        for (final entry in json.entries) {
          if (entry.value is Map<String, dynamic>) {
            _settings[entry.key] = entry.value;
          }
        }
      }
    } catch (e) {
      profileError = 'Could not read control calibration: $e';
    }
    if (!_disposed) retry();
  }

  void retry() {
    _timer?.cancel();
    _bridge?.close();
    _bridge = null;
    selected = null;
    devices = [];
    inputs = [];
    enabled = false;
    usbXinputDetected = false;
    error = null;
    _ticks = 0;
    cancelCalibration();
    identifyingControl = null;
    try {
      final bridge = NativeBridge();
      bridge.start();
      _bridge = bridge;
      trusted = bridge.trusted;
      initialized = true;
      _poll();
      _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _poll());
      if (kDebugMode) debugPrint('HID bridge ready. Accessibility: $trusted.');
    } catch (e) {
      error = e.toString();
      initialized = true;
      if (kDebugMode) debugPrint('HID bridge initialization failed: $e');
    }
    notifyListeners();
  }

  void _poll() {
    final bridge = _bridge;
    if (bridge == null) return;
    if (_ticks++ % 30 == 0) {
      devices = bridge.devices();
      usbXinputDetected = bridge.usbXinputDetected;
      trusted = bridge.trusted;
      if (!trusted && enabled) setEnabled(false);
      if (selected != null && !devices.any((d) => d.id == selected!.id)) {
        bridge.clearMappings();
        enabled = false;
        selected = null;
        cancelCalibration();
        identifyingControl = null;
        inputs = [];
        activity.insert(0, 'Controller disconnected · mappings paused');
      }
      if (selected == null && devices.isNotEmpty) select(devices.first);
      if (selected != null) {
        selected = devices.firstWhere((d) => d.id == selected!.id);
      }
    }
    if (selected != null) {
      acceptInputs(bridge.inputs(selected!.id));
    }
    notifyListeners();
  }

  void select(HidDevice device) {
    final bridge = _bridge!;
    bridge.clearMappings();
    enabled = false;
    selected = device;
    cancelCalibration();
    identifyingControl = null;
    inputs = bridge.inputs(device.id);
    activity = [];
    for (final input in inputs.where((i) => i.isButton)) {
      bridge.map(device.id, input.cookie, keyFor(input));
    }
    notifyListeners();
  }

  Future<void> map(HidInput input, int key) async {
    if (selected == null || !input.isButton) return;
    try {
      _bridge!.map(selected!.id, input.cookie, key);
      final profile = _profiles.putIfAbsent(selected!.profileId, () => {});
      if (key == -1) {
        profile.remove(input.bindingId);
      } else {
        profile[input.bindingId] = key;
      }
      notifyListeners();
      await _save();
    } catch (e) {
      profileError = '$e';
      notifyListeners();
    }
  }

  Future<void> _save() {
    final contents = const JsonEncoder.withIndent('  ').convert(_profiles);
    _pendingSave = _pendingSave
        .then((_) async {
          await _profileFile.parent.create(recursive: true);
          final temporary = File('${_profileFile.path}.tmp');
          await temporary.writeAsString(contents, flush: true);
          await temporary.rename(_profileFile.path);
          profileError = null;
        })
        .catchError((Object e) {
          profileError =
              'Mappings work this session, but could not be saved: $e';
        });
    return _pendingSave.whenComplete(() {
      if (!_disposed) notifyListeners();
    });
  }

  /// Feed a native snapshot through the same path used by the polling loop.
  /// Press counters and native extrema preserve input that occurs between frames.
  void acceptInputs(List<HidInput> next) {
    final previous = {for (final input in inputs) input.cookie: input};
    for (final input in next) {
      final old = previous[input.cookie];
      if (old != null && old.changes != input.changes) {
        final description = input.isHat
            ? input.hatLabel
            : input.isButton
            ? (input.pressed ? 'pressed' : 'released')
            : '${input.value}';
        activity.insert(0, '${labelFor(input)} · $description');
      }
    }
    if (identifyingControl != null) {
      final candidates = next
          .where(
            (i) =>
                i.isButton &&
                i.presses > (_identifyBaseline[i.cookie] ?? i.presses),
          )
          .toList();
      if (candidates.length == 1) {
        final control = identifyingControl!;
        _assignLabel(candidates.single, control);
        identificationMessage =
            'Identified $control as HID button ${candidates.single.usage}.';
        identifyingControl = null;
      } else if (candidates.length > 1) {
        identificationMessage =
            'More than one button was pressed. Release them and press only $identifyingControl.';
        for (final i in next) {
          _identifyBaseline[i.cookie] = i.presses;
        }
      }
    }
    inputs = next;
    if (samplingCenter && stickInputs.isNotEmpty) {
      for (final input in stickInputs) {
        _centerSums.update(
          input.bindingId,
          (v) => v + input.value,
          ifAbsent: () => input.value.toDouble(),
        );
        final old = _draft[input.bindingId]!;
        _draft[input.bindingId] = AxisCalibration(
          old.minimum < input.observedMinimum
              ? old.minimum
              : input.observedMinimum.toDouble(),
          old.center,
          old.maximum > input.observedMaximum
              ? old.maximum
              : input.observedMaximum.toDouble(),
        );
      }
      _centerSamples++;
      if (_centerSamples >= 30) {
        samplingCenter = false;
        final moved = stickInputs.any(
          (i) =>
              _draft[i.bindingId]!.maximum - _draft[i.bindingId]!.minimum >
              (i.maximum - i.minimum) * 0.025,
        );
        if (moved) {
          calibrationMessage = 'The sticks moved while measuring center. Release them and capture center again.';
        } else if (_refreshExtrema()) {
          for (final input in stickInputs) {
            final center = _centerSums[input.bindingId]! / _centerSamples;
            _draft[input.bindingId] = AxisCalibration(center, center, center);
          }
          awaitingCenter = false;
          capturingRange = true;
          calibrationMessage = 'Rotate both sticks around their full outer edges several times, then release them and save the range.';
        }
      }
    } else if (capturingRange) {
      for (final input in stickInputs) {
        final old = _draft[input.bindingId];
        if (old == null) continue;
        _draft[input.bindingId] = AxisCalibration(
          input.observedMinimum < old.minimum
              ? input.observedMinimum.toDouble()
              : old.minimum,
          old.center,
          input.observedMaximum > old.maximum
              ? input.observedMaximum.toDouble()
              : old.maximum,
        );
      }
    }
    if (activity.length > 60) activity.removeRange(60, activity.length);
    notifyListeners();
  }

  void identify(String? control) {
    setEnabled(false);
    cancelCalibration();
    identificationMessage = null;
    identifyingControl = control;
    _identifyBaseline.clear();
    final snapshot = selected == null
        ? inputs
        : _bridge?.inputs(selected!.id) ?? inputs;
    for (final input in snapshot) {
      _identifyBaseline[input.cookie] = input.presses;
    }
    notifyListeners();
  }

  void _assignLabel(HidInput input, String label) {
    final labels = settings.putIfAbsent(
      'labels',
      () => <String, dynamic>{},
    ) as Map<String, dynamic>;
    labels.removeWhere((key, value) => value == label);
    labels[input.bindingId] = label;
    _saveSettings();
  }

  bool _refreshExtrema() {
    try {
      if (_bridge != null && selected != null) {
        _bridge!.resetExtrema(selected!.id);
        inputs = _bridge!.inputs(selected!.id);
      }
      return true;
    } catch (e) {
      cancelCalibration();
      calibrationMessage = '$e';
      return false;
    }
  }

  void startCalibration() {
    setEnabled(false);
    identifyingControl = null;
    identificationMessage = null;
    _draft.clear();
    awaitingCenter = true;
    samplingCenter = false;
    capturingRange = false;
    calibrationMessage =
        'Release both sticks and leave them at rest, then capture the center.';
    notifyListeners();
  }

  void captureCenter() {
    if (!awaitingCenter ||
        samplingCenter ||
        stickInputs.isEmpty ||
        !_refreshExtrema()) {
      return;
    }
    _draft.clear();
    _centerSums.clear();
    _centerSamples = 0;
    for (final input in stickInputs) {
      final center = input.value.toDouble();
      _draft[input.bindingId] = AxisCalibration(center, center, center);
    }
    samplingCenter = true;
    calibrationMessage =
        'Measuring center for half a second. Keep both sticks untouched.';
    notifyListeners();
  }

  String rangeFor(HidInput input) {
    final draft = _draft[input.bindingId];
    return draft == null
        ? ''
        : '${draft.minimum.round()} … ${draft.maximum.round()}';
  }

  bool saveCalibration() {
    if (!capturingRange) return false;
    for (final input in stickInputs) {
      final draft = _draft[input.bindingId];
      final threshold = (input.maximum - input.minimum).abs() * 0.15;
      if (draft == null ||
          !draft.valid ||
          draft.center - draft.minimum < threshold ||
          draft.maximum - draft.center < threshold) {
        calibrationMessage = 'Move every stick axis fully in both directions. If the center was captured while tilted, cancel and start again.';
        notifyListeners();
        return false;
      }
    }
    if (stickInputs.isEmpty) return false;
    if (stickInputs.any(
      (i) =>
          (i.value - _draft[i.bindingId]!.center).abs() >
          (i.maximum - i.minimum) * 0.05,
    )) {
      calibrationMessage = 'Release both sticks before saving so their resting position can be checked.';
      notifyListeners();
      return false;
    }
    settings['calibration'] = {
      for (final entry in _draft.entries) entry.key: entry.value.toJson(),
    };
    capturingRange = false;
    _draft.clear();
    calibrationMessage = 'Calibration saved for this connection mode. Raw HID values remain available below.';
    _saveSettings();
    notifyListeners();
    return true;
  }

  void cancelCalibration() {
    awaitingCenter = false;
    samplingCenter = false;
    capturingRange = false;
    _draft.clear();
    calibrationMessage = null;
    if (!_disposed) notifyListeners();
  }

  void resetCalibration() {
    settings.remove('calibration');
    cancelCalibration();
    _saveSettings();
  }

  void setDeadzone(double value, {bool save = true}) {
    settings['deadzone'] = value.clamp(0, 0.5);
    if (save) _saveSettings();
    notifyListeners();
  }

  Future<void> _saveSettings() {
    if (!persistSettings) return Future.value();
    final contents = const JsonEncoder.withIndent('  ').convert(_settings);
    _pendingSettingsSave = _pendingSettingsSave
        .then((_) async {
          await _settingsFile.parent.create(recursive: true);
          final temporary = File('${_settingsFile.path}.tmp');
          await temporary.writeAsString(contents, flush: true);
          await temporary.rename(_settingsFile.path);
        })
        .catchError((Object e) {
          profileError = 'Could not save control settings: $e';
        });
    return _pendingSettingsSave.whenComplete(() {
      if (!_disposed) notifyListeners();
    });
  }

  void setEnabled(bool value) {
    if (value && (selected == null || mappings.isEmpty)) return;
    enabled = _bridge?.enable(value) == true && value;
    trusted = _bridge?.trusted ?? false;
    notifyListeners();
  }

  void requestAccessibility() {
    _bridge?.requestAccessibility();
    refreshAccessibility();
  }

  void refreshAccessibility() {
    trusted = _bridge?.trusted ?? false;
    if (!trusted && enabled) {
      _bridge?.enable(false);
      enabled = false;
    }
    notifyListeners();
  }

  void clearActivity() {
    activity = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _bridge?.close();
    super.dispose();
  }
}
