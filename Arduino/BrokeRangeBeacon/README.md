# Broke Range Beacon

This firmware turns the Arduino UNO R4 WiFi into a stationary BLE beacon named
`BROKE-RANGE`. The iPhone measures the beacon's RSSI; the Arduino cannot derive
an accurate physical distance by itself.

## First accuracy test

1. Keep the Arduino in one fixed position and orientation.
2. Open a BLE scanner on the iPhone, such as nRF Connect or LightBlue.
3. Find `BROKE-RANGE` and watch its RSSI without connecting.
4. Hold the phone in the same orientation at each test point.
5. Record at least 20 seconds of readings at 0.5 m, 1 m, 2 m, 3 m, and across
   the intended room boundary.
6. Use the median RSSI at 1 m as the calibration value.

RSSI is intentionally treated as a proximity signal, not a tape measure.
Walls, people, pockets, phone orientation, and reflections can easily change
readings by 5-15 dB.

## Serial monitor

Use 115200 baud. Available commands:

```text
help
status
cal -62
threshold -70
```

The calibration and threshold values reset when the board restarts. The iPhone
app can later write and persist its chosen values.

## BLE identifiers

```text
Service:     6f2a0001-8f4d-4b1a-9f1c-7d19d2a10001
Calibration: 6f2a0002-8f4d-4b1a-9f1c-7d19d2a10001
Threshold:   6f2a0003-8f4d-4b1a-9f1c-7d19d2a10001
Version:     6f2a0004-8f4d-4b1a-9f1c-7d19d2a10001
Pod ID:      6f2a0005-8f4d-4b1a-9f1c-7d19d2a10001
```

This prototype pod identifies itself as `BRK-F412FA9FF241`. Production units
must each receive a different factory-provisioned pod ID.
