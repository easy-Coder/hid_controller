import 'package:flutter/material.dart';

import '../controller/controller_store.dart';
import '../controller/models.dart';
import '../controller/calibration.dart';

const accent = Color(0xFFC4F277);
const muted = Color(0xFF939BAA);
const border = Color(0xFF2B303A);

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.store});
  final ControllerStore store;
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> with WidgetsBindingObserver {
  int page = 0;
  String controlToIdentify = 'A';
  ControllerStore get store => widget.store;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) store.refreshAccessibility();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 850;
          return Row(
            children: [
              if (wide) _sidebar(),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 26, 28, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  const [
                                    'Input tester',
                                    'Key mappings',
                                    'Raw HID data',
                                  ][page],
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.8,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  const [
                                    'Get to know every input.',
                                    'Make your controller work your way.',
                                    'Inspect what macOS receives.',
                                  ][page],
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _badge(
                            store.selected == null
                                ? 'Waiting for controller'
                                : 'Connected',
                            store.selected != null,
                          ),
                        ],
                      ),
                    ),
                    if (!wide)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 0, label: Text('Test')),
                            ButtonSegment(value: 1, label: Text('Map')),
                            ButtonSegment(value: 2, label: Text('Raw')),
                          ],
                          selected: {page},
                          onSelectionChanged: (s) =>
                              setState(() => page = s.first),
                        ),
                      ),
                    const Divider(height: 1, color: border),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!wide && store.devices.isNotEmpty) ...[
                              _devicePicker(),
                              const SizedBox(height: 20),
                            ],
                            if (store.error != null) _error(),
                            if (store.profileError != null) ...[
                              _notice(store.profileError!),
                              const SizedBox(height: 16),
                            ],
                            if (store.error == null && store.selected == null)
                              _empty(),
                            if (store.selected != null) ...[
                              _deviceHeader(),
                              const SizedBox(height: 22),
                              if (page == 0) _tester(),
                              if (page == 1) _mappings(),
                              if (page == 2) _raw(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: border)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.bluetooth, size: 14, color: muted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              store.selected?.transport ??
                                  'GameSir Nova Lite · Bluetooth',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            store.enabled
                                ? 'Keyboard output on'
                                : 'Keyboard output paused',
                            style: TextStyle(
                              fontSize: 12,
                              color: store.enabled ? accent : muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
  Widget _sidebar() => Container(
    width: 236,
    padding: const EdgeInsets.all(20),
    decoration: const BoxDecoration(
      color: Color(0xFF15181E),
      border: Border(right: BorderSide(color: border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Row(
          children: [
            Icon(Icons.sports_esports_outlined, color: accent, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Controller Lab',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 38),
        const Text(
          'WORKSPACE',
          style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.8),
        ),
        const SizedBox(height: 14),
        for (final entry in [
          (Icons.gamepad_outlined, 'Input tester'),
          (Icons.keyboard_outlined, 'Key mappings'),
          (Icons.data_object, 'Raw HID data'),
        ].indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Material(
              color: page == entry.$1
                  ? const Color(0xFF293122)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => page = entry.$1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        entry.$2.$1,
                        size: 19,
                        color: page == entry.$1 ? accent : muted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          entry.$2.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: page == entry.$1 ? accent : muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 32),
        const Text(
          'DEVICES',
          style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.8),
        ),
        const SizedBox(height: 14),
        if (store.devices.isEmpty)
          const Text(
            'No controller connected',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        if (store.devices.isNotEmpty) _devicePicker(),
        const Spacer(),
        const Divider(color: border),
        const SizedBox(height: 12),
        const Text(
          'Your controller, decoded.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
  Widget _devicePicker() => DropdownButtonFormField<int>(
    key: ValueKey(store.selected?.id),
    initialValue: store.selected?.id,
    isExpanded: true,
    items: [
      for (final d in store.devices)
        DropdownMenuItem(
          value: d.id,
          child: Text(d.name, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (id) {
      if (id != null) store.select(store.devices.firstWhere((d) => d.id == id));
    },
  );
  Widget _badge(String text, bool active) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: active ? const Color(0xFF293122) : const Color(0xFF20242D),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? accent : muted,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: active ? accent : muted),
        ),
      ],
    ),
  );
  Widget _panel({required Widget child}) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: const Color(0xFF191C23),
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
  Widget _notice(String message) => _panel(
    child: Text(message, style: const TextStyle(color: Color(0xFFE8BE77))),
  );
  Widget _error() => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Unable to start the HID bridge',
          style: TextStyle(fontSize: 20),
        ),
        const SizedBox(height: 12),
        Text(store.error!, style: const TextStyle(color: muted)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: store.retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry connection'),
        ),
      ],
    ),
  );
  Widget _empty() => _panel(
    child: Column(
      children: [
        const SizedBox(height: 46),
        Container(
          padding: const EdgeInsets.all(28),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF252B20),
          ),
          child: const Icon(
            Icons.sports_esports_outlined,
            size: 64,
            color: accent,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          store.usbXinputDetected
              ? 'USB controller found'
              : store.initialized
              ? 'Ready when you are.'
              : 'Starting the HID bridge…',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          store.usbXinputDetected
              ? 'Your Nova Lite is reporting as “XBOX 360 For Windows”.\nThis USB mode does not expose a standard HID gamepad.'
              : 'Connect your Nova Lite by USB or macOS Bluetooth.\nIts inputs will appear here automatically.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 14, height: 1.7),
        ),
        const SizedBox(height: 26),
        OutlinedButton.icon(
          onPressed: store.retry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Scan again'),
        ),
        const SizedBox(height: 36),
        Text(
          store.usbXinputDetected
              ? 'Close Keyboard Setup Assistant and keep the USB cable connected.\nHold View + Menu for about 2 seconds to cycle modes.\nTry DS4 or NS/Switch mode, then select Scan again.\nKeyboard identification is not needed to test a gamepad.'
              : 'Check that the controller is connected and awake.\nIf macOS blocks input, allow Controller Lab under Privacy & Security → Input Monitoring.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 28),
      ],
    ),
  );
  Widget _deviceHeader() => _panel(
    child: Row(
      children: [
        const Icon(Icons.sports_esports_outlined, size: 38, color: accent),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                store.selected!.name,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${store.selected!.transport}  ·  ${store.selected!.identity}  ·  ${store.inputs.length} inputs',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _title(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 20),
    ],
  );
  Widget _tester() {
    final axes = store.inputs.where((i) => i.isAxis).toList();
    final buttons = store.inputs.where((i) => i.isButton).toList();
    final hats = store.inputs.where((i) => i.isHat).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(
                'Sticks & calibration',
                'Calibrate the resting center and full travel of LS and RS. Raw values stay unchanged.',
              ),
              if (axes.isEmpty)
                const Text(
                  'No analog axes reported.',
                  style: TextStyle(color: muted),
                ),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                children: [
                  for (final stick in store.sticks)
                    SizedBox(
                      width: 190,
                      child: Column(
                        children: [
                          SizedBox(
                            width: 150,
                            height: 150,
                            child: CustomPaint(
                              painter: AxisPainter(
                                store.reading(stick).x,
                                store.reading(stick).y,
                                deadzone: store.deadzone,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            stick.name,
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'X ${store.reading(stick).x.toStringAsFixed(3)}  Y ${store.reading(stick).y.toStringAsFixed(3)}',
                            style: const TextStyle(
                              fontFamily: 'Menlo',
                              fontSize: 11,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (store.sticks.isNotEmpty) ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (!store.awaitingCenter && !store.capturingRange)
                      FilledButton.icon(
                        onPressed: store.startCalibration,
                        icon: const Icon(Icons.tune, size: 18),
                        label: const Text('Calibrate sticks'),
                      ),
                    if (store.awaitingCenter)
                      FilledButton(
                        onPressed: store.samplingCenter
                            ? null
                            : store.captureCenter,
                        child: Text(
                          store.samplingCenter
                              ? 'Measuring center…'
                              : 'Capture center',
                        ),
                      ),
                    if (store.capturingRange)
                      FilledButton(
                        onPressed: store.saveCalibration,
                        child: const Text('Save range'),
                      ),
                    if (store.awaitingCenter || store.capturingRange)
                      TextButton(
                        onPressed: store.cancelCalibration,
                        child: const Text('Cancel'),
                      ),
                    if (store.calibrated &&
                        !store.awaitingCenter &&
                        !store.capturingRange)
                      TextButton(
                        onPressed: store.resetCalibration,
                        child: const Text('Reset calibration'),
                      ),
                    Text(
                      store.calibrated
                          ? 'Saved calibration'
                          : 'Descriptor range · not calibrated',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (store.calibrationMessage != null) ...[
                  Text(
                    store.calibrationMessage!,
                    style: const TextStyle(color: accent, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Text(
                      'Dead zone ${(store.deadzone * 100).round()}%',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    Expanded(
                      child: Slider(
                        value: store.deadzone,
                        min: 0,
                        max: 0.5,
                        divisions: 50,
                        onChanged: (value) =>
                            store.setDeadzone(value, save: false),
                        onChangeEnd: store.setDeadzone,
                      ),
                    ),
                  ],
                ),
                const Text(
                  'Calibration and dead zone affect this tester only. Games still receive the original controller input.',
                  style: TextStyle(color: muted, fontSize: 11, height: 1.5),
                ),
                const SizedBox(height: 20),
              ],
              for (final axis in axes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text(
                          axis.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (store.capturingRange)
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text(
                            store.rangeFor(axis),
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                        ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: axis.fraction,
                            minHeight: 6,
                            color: accent,
                            backgroundColor: border,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 70,
                        child: Text(
                          '${axis.value}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontFamily: 'Menlo',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _title(
                'Buttons & D-pad',
                'Digital controls report pressed or released. Identify each physical button to give it a name.',
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String>(
                      initialValue: controlToIdentify,
                      decoration: const InputDecoration(
                        labelText: 'Physical control',
                      ),
                      items: [
                        for (final name in controlNames)
                          DropdownMenuItem(value: name, child: Text(name)),
                      ],
                      onChanged: (name) {
                        if (name != null) {
                          store.identify(null);
                          setState(() => controlToIdentify = name);
                        }
                      },
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => store.identify(controlToIdentify),
                    child: const Text('Press to identify'),
                  ),
                  if (store.identifyingControl != null)
                    TextButton(
                      onPressed: () => store.identify(null),
                      child: const Text('Cancel'),
                    ),
                ],
              ),
              if (store.identifyingControl != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Press ${store.identifyingControl} on your controller now. Keyboard output is paused.',
                    style: const TextStyle(color: accent),
                  ),
                ),
              if (store.isSwitchMode)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Switch mode exposes LT/RT as digital buttons, so trigger pressure percentages are unavailable in this mode.',
                    style: TextStyle(fontSize: 12, color: muted, height: 1.5),
                  ),
                ),
              if (store.identificationMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    store.identificationMessage!,
                    style: const TextStyle(color: accent),
                  ),
                ),
              const SizedBox(height: 18),
              if (buttons.isEmpty)
                const Text(
                  'No buttons reported.',
                  style: TextStyle(color: muted),
                ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final button in buttons)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: button.pressed
                            ? accent
                            : const Color(0xFF222630),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: button.pressed ? accent : border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            store.labelFor(button),
                            style: TextStyle(
                              color: button.pressed
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${button.pressed ? 'Pressed' : 'Released'} · ${button.value}',
                            style: TextStyle(
                              color: button.pressed ? Colors.black87 : muted,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'HID ${button.usage} · ${button.changes} changes',
                            style: TextStyle(
                              color: button.pressed ? Colors.black54 : muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              for (final hat in hats)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.control_camera, color: accent),
                      const SizedBox(width: 10),
                      Text('${hat.label}: ${hat.hatLabel}'),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Input activity',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: store.clearActivity,
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (store.activity.isEmpty)
                const Text(
                  'Waiting for your first input…',
                  style: TextStyle(color: muted),
                ),
              for (final event in store.activity.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(
                    event,
                    style: const TextStyle(
                      fontSize: 12,
                      color: muted,
                      fontFamily: 'Menlo',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mappings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Keyboard output',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        store.enabled
                            ? 'Mapped keys are sent to the focused app.'
                            : 'Paused. Choose your bindings, then enable output.',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: store.enabled,
                  onChanged: store.trusted && store.mappings.isNotEmpty
                      ? store.setEnabled
                      : null,
                ),
              ],
            ),
            if (!store.trusted) ...[
              const SizedBox(height: 18),
              const Text(
                'macOS has not authorized this running build to send keyboard events. Allow Controller Lab in System Settings → Privacy & Security → Accessibility. If it is already checked, quit the app, remove its old entry, then add this app again and reopen it.',
                style: TextStyle(color: muted, height: 1.5),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: store.requestAccessibility,
                    icon: const Icon(Icons.lock_open, size: 18),
                    label: const Text('Grant Accessibility access'),
                  ),
                  OutlinedButton.icon(
                    onPressed: store.refreshAccessibility,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Check permission again'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(
              'Button bindings',
              'Saved automatically for this device and connection type. Key labels assume a US keyboard.',
            ),
            if (!store.inputs.any((i) => i.isButton))
              const Text(
                'No mappable buttons reported.',
                style: TextStyle(color: muted),
              ),
            for (final input in store.inputs.where((i) => i.isButton))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: input.pressed ? accent : border,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(store.labelFor(input))),
                    const Icon(Icons.arrow_forward, color: muted, size: 16),
                    const SizedBox(width: 22),
                    SizedBox(
                      width: 160,
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('${input.cookie}:${store.keyFor(input)}'),
                        initialValue: store.keyFor(input),
                        isExpanded: true,
                        items: [
                          for (final key in keyboardKeys.entries)
                            DropdownMenuItem(
                              value: key.key,
                              child: Text(key.value),
                            ),
                        ],
                        onChanged: (key) {
                          if (key != null) store.map(input, key);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'This version maps digital buttons. Analog axes and hat switches are available in the tester.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.6),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _raw() => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'HID elements',
          store.isSwitchMode
              ? 'Decoded Switch report fields. Sticks use 12-bit values; Y increases downward. Counters retain transitions between frames.'
              : 'Raw values and logical ranges reported by IOHIDManager. Changes counts every native value transition.',
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 26,
            columns: [
              for (final label in [
                'Input',
                'Cookie',
                'Page / Usage',
                'Value',
                'Min',
                'Max',
                'Changes',
              ])
                DataColumn(label: Text(label)),
            ],
            rows: [
              for (final i in store.inputs)
                DataRow(
                  cells: [
                    DataCell(Text(store.labelFor(i))),
                    DataCell(Text('${i.cookie}')),
                    DataCell(
                      Text(
                        '${i.page.toRadixString(16)} / ${i.usage.toRadixString(16)}',
                      ),
                    ),
                    DataCell(
                      Text(
                        '${i.value}',
                        style: TextStyle(color: i.pressed ? accent : null),
                      ),
                    ),
                    DataCell(Text('${i.minimum}')),
                    DataCell(Text('${i.maximum}')),
                    DataCell(Text('${i.changes}')),
                  ],
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class AxisPainter extends CustomPainter {
  AxisPainter(this.x, this.y, {this.deadzone = 0});
  final double x, y;
  final double deadzone;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    canvas.drawCircle(
      center,
      radius * deadzone,
      Paint()..color = accent.withValues(alpha: 0.08),
    );
    final paint = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius / 2, paint);
    canvas.drawLine(
      Offset(center.dx, 8),
      Offset(center.dx, size.height - 8),
      paint,
    );
    canvas.drawLine(
      Offset(8, center.dy),
      Offset(size.width - 8, center.dy),
      paint,
    );
    final point = center + Offset(x * radius, y * radius);
    canvas.drawLine(
      center,
      point,
      Paint()
        ..color = accent.withValues(alpha: 0.35)
        ..strokeWidth = 2,
    );
    canvas.drawCircle(point, 6, Paint()..color = accent);
    canvas.drawCircle(center, 2, Paint()..color = muted);
  }

  @override
  bool shouldRepaint(AxisPainter oldDelegate) =>
      x != oldDelegate.x ||
      y != oldDelegate.y ||
      deadzone != oldDelegate.deadzone;
}
