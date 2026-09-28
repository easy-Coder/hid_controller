# Controller Lab

A native macOS controller tester and button-to-key mapper for a GameSir Nova Lite over Bluetooth. It discovers any HID joystick, gamepad, or multi-axis controller exposed by macOS; it does not depend on a hardcoded GameSir vendor ID or button layout.

## Run

Requirements: macOS 11+, Xcode with command-line tools, Flutter with Dart 3.13+, and **Zig 0.15.2**.

```sh
flutter pub get
flutter run -d macos
```

The Xcode build phase compiles, bundles, and signs the Zig dylib automatically. If Zig 0.15.2 is installed at `~/.zvm/0.15.2/zig`, the script uses it. Otherwise put Zig 0.15.2 on PATH or set its location explicitly:

```sh
ZIG=/absolute/path/to/zig-0.15.2/zig flutter run -d macos
```

The installed Zig master is not used when the pinned version is available. Zig 0.17 removed `@cImport`; this bridge uses the Zig 0.15.2 C interop API.

Connect the Nova Lite using macOS Bluetooth settings, wake it, and open Controller Lab. Bluetooth pairing remains managed by macOS. The app detects connections and disconnections automatically.

### USB detected as an external keyboard

The observed Nova Lite Xbox USB persona (`3537:1040`, named `XBOX 360 For Windows`) exposes keyboard and vendor-specific HID interfaces, with no standard HID gamepad interface on this Mac. Keyboard Setup Assistant does not configure its gamepad inputs. Controller Lab now checks USB metadata and explains this state without opening or monitoring the keyboard interface.

Close Keyboard Setup Assistant, leave USB connected, and hold **View + Menu for about 2 seconds** to cycle wired modes. Try **DS4 or NS/Switch** mode, then select Scan again. The app can read inputs once macOS exposes a gamepad descriptor. Firmware versions differ; this does not guarantee every mode will work on every firmware. See [GameSir's Nova Lite FAQ](https://gamesir.com/pages/faq-questions-about-nova-lite) and [Nova Lite manual](https://gamesir.es/wp-content/uploads/Nova_Lite_Manual.pdf).

Direct USB Xbox/XInput protocol decoding is not implemented by the IOHIDManager backend. The keyboard interface is not treated as a substitute for controller buttons and axes.

## Features

- Device selection, product name, connection transport, and vendor/product IDs.
- Live button highlights with raw states and transition counts, named LS/RS plots, raw axis values, and D-pad hat directions.
- Saved stick calibration with captured resting center and observed endpoints, plus a radial dead zone.
- Physical button identification: choose a control name, then press its button; labels persist and appear in mappings and activity.
- Input fields with usage page, usage, cookie, range, and transition count. Switch reports are decoded before reaching the UI.
- Digital button-to-key bindings, automatically saved per vendor/product/transport profile.
- Explicit keyboard output switch, paused at launch, reconnection, and device selection.
- Native key-up cleanup on disable, remapping, disconnect, and normal app termination. Buttons sharing one keyboard key use a reference count so releasing one does not release the other.

Switch buttons start with canonical physical-position or control names. Other devices start with HID numbers; firmware modes and face-button swaps can change their meaning. Choose a name under Physical control, click Press to identify, then press that control. Its saved name appears in the tester, mappings, activity, and raw data. Digital buttons naturally report pressed/released; the connected Pro Controller/Switch descriptor also reports triggers as digital buttons rather than analog pressure axes.

Stick plots pair axes by usage: X/Y for LS, Rx/Ry for RS when present, otherwise Z/Rz for Switch/DS4-style descriptors. Click Calibrate sticks, release both sticks, and click Capture center. The app averages 30 snapshots (about half a second) and rejects movement during center measurement. Rotate both sticks around their full outer edges several times, then release them and click Save range. Native callbacks track travel extremes even if the UI misses a frame. Saving rejects very small travel and sticks that have not returned to their measured center. Saving requires movement on both sides of every captured center. The app uses separate positive/negative spans to normalize each axis around zero. Adjust Dead zone to filter small resting noise; Reset calibration returns to the descriptor's logical ranges. Calibration changes this tester's visualization only, not controller firmware or the input received by games. Keyboard output pauses during calibration and button identification.

Calibration, dead zone, and control labels are saved per connection profile in `~/Library/Application Support/Controller Lab/controls.json`. Generic HID values remain unmodified. Switch fields are decoded from full/simple report bytes into a consistent 12-bit range with Y pointing down; these are decoded values, not the incorrect simple-descriptor interpretation of an extended report. The activity list shows the latest sampled values; native transition counters retain changes between UI polls.

## Permissions

Reading controller inputs may require **Input Monitoring** in System Settings → Privacy & Security. If the controller is connected but inputs do not appear, allow Controller Lab there and restart it or use Scan again.

Sending keyboard events requires **Accessibility**. Use Grant Accessibility access in Key mappings, enable Controller Lab in System Settings, then turn on Keyboard output. Output goes to the focused application, and this app must remain running. Granting permission never enables mappings automatically.

This local utility disables App Sandbox to support system-wide keyboard output. The build is locally signed; it is not notarized or prepared for App Store distribution.

The Runner target uses the Apple Development identity available on this Mac (team `4XQNPK9C94`) so its designated requirement remains consistent across rebuilds. On another Mac, select your own development signing identity in Xcode. Switching from the earlier ad-hoc signature requires granting Accessibility to the new build once: quit Controller Lab, remove the old entry from Accessibility, add the current app from `build/macos/Build/Products/Debug/Controller Lab.app`, then reopen it. A checked entry for an older signature is not proof that the running build is authorized. The app rechecks on return from System Settings and also offers Check permission again; it never enables keyboard output automatically.

## Architecture

```text
Flutter UI
    │ ControllerStore: device selection, profiles, sampled activity
    │ dart:ffi: versioned C ABI, copied device/input snapshots
    ▼
Zig dylib
    ├─ pthread + Core Foundation run loop
    ├─ IOHIDManager: discovery, removal, input value callbacks
    ├─ mutex: protect state shared with Dart
    └─ Core Graphics: mapped keyboard down/up events
```

- `lib/ui/dashboard.dart`: input tester, mappings, and raw data screens.
- `lib/controller/native_bridge.dart`: manual Dart FFI bindings matching `native/controller.h`.
- `lib/controller/controller_store.dart`: lifecycle, selection, JSON profiles, and approximately 60 Hz input snapshots. Discovery and permission checks run approximately twice per second.
- `native/src/controller.zig`: macOS integration. Mapping events run on native callbacks, independent of Flutter's polling rate.
- `native/src/key_state.zig`: shared-key state and native unit tests.
- `native/src/switch_report.zig`: Switch full/simple packet decoding with captured Nova Lite fixtures and tests isolating each stick axis.
- `scripts/build_native.sh`: Zig object compilation followed by Apple's linker, avoiding compatibility problems with newer Xcode SDK stubs. Uses Xcode's requested architectures for the bundled library.

Profiles are stored in `~/Library/Application Support/Controller Lab/profiles.json`. Bindings include usage page, usage, and cookie. A changed firmware/connection descriptor may require mapping again. The same device model and transport share a profile. Save failures appear in the UI.

The ABI currently supports 16 devices and 128 input elements per device. It exposes only input elements, never keyboard or mouse discovery. Native snapshots own no device pointers, so Dart never holds an IOHID object after disconnect.

## Verify

```sh
flutter analyze
flutter test
bash scripts/test_native.sh
flutter build macos --debug
```

The native suite checks shared-key releases, duplicate transitions, captured Switch packets, and independent stick axes. It loads the real dylib, checks ABI v2 struct layout, and runs five startup/shutdown cycles. Native snapshots also retain button press counts and resettable axis extrema. It does not inject keyboard events. Flutter tests cover FFI layout, signed axis ranges, neutral hat values, responsive empty states, and connected test/mapping/raw screens.

Physical verification:

1. Connect the Nova Lite over Bluetooth and select it.
2. Exercise every button, stick, trigger, and D-pad direction; check Raw HID data to identify their elements.
3. Assign a digital button to Space, grant Accessibility, and enable output.
4. Focus a text editor and press/release that button.
5. Hold the mapped button and disconnect the controller; confirm the key releases and output is paused after reconnection.

The connected Nova Lite was subsequently verified to send 64-byte `0x30` full Switch reports. The original simple-HID interpretation incorrectly mixed timer/button bytes into axis and button state. The native decoder now produces four near-center stick values and no phantom presses from the captured resting report. Identification uses press counters to catch taps between UI polls. Legacy descriptor cookies differ from the new decoded field cookies, so incorrect earlier calibration, labels, and key bindings are ignored for the corrected fields; calibrate and assign bindings again. Actual physical rolls and keyboard delivery still require the checklist above.

## Current scope

Digital buttons map to individual keyboard keys at physical macOS key positions (labels assume a US layout). Native controller input remains available to games; this app does not suppress or rewrite it. This version does not yet provide analog/D-pad-to-key mappings, key combinations, macros, mouse output, virtual gamepad remapping, rumble, battery reporting, or controller firmware configuration.

Next additions can build on the existing element descriptors: direction/threshold bindings for sticks and hat switches, per-game profiles, and device-specific output reports for supported hardware.

API references: [Dart FFI](https://dart.dev/interop/c-interop), [IOHIDManager run-loop scheduling](https://developer.apple.com/documentation/iokit/1438409-iohidmanagerschedulewithrunloop), and [Core Graphics events](https://developer.apple.com/documentation/coregraphics/cgevent).

Switch field layout reference: [SDL’s Switch HIDAPI implementation](https://github.com/libsdl-org/SDL/blob/main/src/joystick/hidapi/SDL_hidapi_switch.c).
