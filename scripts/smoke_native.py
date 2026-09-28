"""Exercise the real dylib ABI and repeated startup/shutdown without posting keys."""
import ctypes as c
from pathlib import Path
import time

lib = c.CDLL(str(Path(__file__).resolve().parent.parent / 'build/native/libcontroller_hid.dylib'))

class Device(c.Structure):
    _fields_ = [('id', c.c_uint64), ('vendor', c.c_uint32), ('product', c.c_uint32),
                ('count', c.c_uint32), ('reserved', c.c_uint32),
                ('name', c.c_char * 128), ('transport', c.c_char * 32)]

class Input(c.Structure):
    _fields_ = [('cookie', c.c_uint32), ('page', c.c_uint32), ('usage', c.c_uint32),
                ('kind', c.c_uint32), ('value', c.c_int64), ('minimum', c.c_int64),
                ('maximum', c.c_int64), ('changes', c.c_uint64),
                ('presses', c.c_uint64), ('seen_minimum', c.c_int64), ('seen_maximum', c.c_int64)]

assert c.sizeof(Device) == 184
assert c.sizeof(Input) == 72
assert lib.hc_abi_version() == 2
hint = lib.hc_usb_mode_hint()
assert hint in (0, 1), f'USB registry query failed: {hint}'
print(f'Nova Lite Xbox USB mode detected: {bool(hint)}')
lib.hc_devices.argtypes = [c.POINTER(Device), c.c_uint32]
lib.hc_devices.restype = c.c_uint32
lib.hc_inputs.argtypes = [c.c_uint64, c.POINTER(Input), c.c_uint32]
lib.hc_map.argtypes = [c.c_uint64, c.c_uint32, c.c_int32]
lib.hc_reset_extrema.argtypes = [c.c_uint64]
devices = (Device * 16)()
inputs = (Input * 128)()
for attempt in range(5):
    result = lib.hc_start()
    try:
        assert result == 0, f'IOHIDManager failed to open: {result}'
        if attempt == 0:
            time.sleep(0.1)
            count = lib.hc_devices(devices, 16)
            print(f'Native ABI OK. Connected controllers: {count}')
            for d in devices[:count]:
                n = lib.hc_inputs(d.id, inputs, 128)
                print(f'  {d.name.decode()} ({d.transport.decode()}), {n} inputs')
                if d.vendor == 0x057e and d.product == 0x2009:
                    print(f'  Decoded Switch report: {d.reserved:#x}')
                    print('  Sticks:', [v.value for v in inputs[:n] if v.kind == 2])
                    print('  Pressed:', [v.usage for v in inputs[:n] if v.kind == 1 and v.value])
                    assert n == 19
                    assert d.reserved in (0x30, 0x31, 0x21, 0x3f), 'No decoded Switch reports received'
                assert lib.hc_reset_extrema(d.id) == 0
        assert lib.hc_devices(devices, 0) == 0
        assert lib.hc_inputs(0, inputs, 128) == 0
        assert lib.hc_reset_extrema(0) == -1
        assert lib.hc_map(0, 0, 49) == -2
        assert lib.hc_map(0, 0, 128) == -1
        assert lib.hc_enable(0) == 0
        lib.hc_clear_mappings()
    finally:
        lib.hc_stop()
        lib.hc_stop()
print('Five startup/shutdown cycles passed.')
