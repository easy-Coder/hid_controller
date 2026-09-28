class HidDevice {
  const HidDevice({
    required this.id,
    required this.name,
    required this.transport,
    required this.vendor,
    required this.product,
    required this.inputCount,
    this.reportId = 0,
  });
  final int id, vendor, product, inputCount;
  final int reportId;
  final String name, transport;
  String get profileId => '$vendor:$product:$transport';
  String get identity =>
      '${vendor.toRadixString(16).padLeft(4, '0')}:${product.toRadixString(16).padLeft(4, '0')}';
}

class HidInput {
  const HidInput({
    required this.cookie,
    required this.page,
    required this.usage,
    required this.kind,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.changes,
    this.presses = 0,
    this.seenMinimum,
    this.seenMaximum,
  });
  final int cookie, page, usage, kind, value, minimum, maximum, changes;
  final int presses;
  final int? seenMinimum, seenMaximum;
  int get observedMinimum => seenMinimum ?? value;
  int get observedMaximum => seenMaximum ?? value;
  bool get isButton => kind == 1;
  bool get isAxis => kind == 2;
  bool get isHat => kind == 3;
  bool get pressed => isButton && value != 0;
  String get bindingId => '$page:$usage:$cookie';
  double get fraction => maximum <= minimum
      ? 0
      : ((value - minimum) / (maximum - minimum)).clamp(0, 1).toDouble();
  double get centered => fraction * 2 - 1;
  String get label {
    if (isButton) return 'Button $usage';
    if (isHat) return 'D-pad';
    if (page == 1) {
      return const {
            0x30: 'X axis',
            0x31: 'Y axis',
            0x32: 'Z axis',
            0x33: 'Rx axis',
            0x34: 'Ry axis',
            0x35: 'Rz axis',
            0x36: 'Slider',
            0x37: 'Dial',
            0x38: 'Wheel',
          }[usage] ??
          'Input $usage';
    }
    return 'Usage ${page.toRadixString(16)}:${usage.toRadixString(16)}';
  }

  String get hatLabel {
    final index = value - minimum;
    if (value < minimum || value > maximum || index > 7) return 'Neutral';
    if (maximum - minimum == 3) {
      return const ['Up', 'Right', 'Down', 'Left'][index];
    }
    return const [
      'Up',
      'Up-right',
      'Right',
      'Down-right',
      'Down',
      'Down-left',
      'Left',
      'Up-left',
    ][index];
  }
}

// macOS virtual key codes (physical positions; labels assume a US layout).
const keyboardKeys = <int, String>{
  -1: 'Unmapped',
  0: 'A',
  1: 'S',
  2: 'D',
  3: 'F',
  4: 'H',
  5: 'G',
  6: 'Z',
  7: 'X',
  8: 'C',
  9: 'V',
  11: 'B',
  12: 'Q',
  13: 'W',
  14: 'E',
  15: 'R',
  16: 'Y',
  17: 'T',
  18: '1',
  19: '2',
  20: '3',
  21: '4',
  22: '6',
  23: '5',
  25: '9',
  26: '7',
  28: '8',
  29: '0',
  31: 'O',
  32: 'U',
  34: 'I',
  35: 'P',
  37: 'L',
  38: 'J',
  40: 'K',
  45: 'N',
  46: 'M',
  36: 'Return',
  48: 'Tab',
  49: 'Space',
  51: 'Delete',
  53: 'Escape',
  123: '← Left',
  124: '→ Right',
  125: '↓ Down',
  126: '↑ Up',
};
