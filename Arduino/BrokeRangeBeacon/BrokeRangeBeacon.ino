#include <ArduinoBLE.h>

namespace {
constexpr char kDeviceName[] = "BROKE-RANGE";
constexpr char kServiceUuid[] = "6f2a0001-8f4d-4b1a-9f1c-7d19d2a10001";
constexpr char kCalibrationUuid[] = "6f2a0002-8f4d-4b1a-9f1c-7d19d2a10001";
constexpr char kThresholdUuid[] = "6f2a0003-8f4d-4b1a-9f1c-7d19d2a10001";
constexpr char kVersionUuid[] = "6f2a0004-8f4d-4b1a-9f1c-7d19d2a10001";
constexpr char kPodIdUuid[] = "6f2a0005-8f4d-4b1a-9f1c-7d19d2a10001";
constexpr char kHeartbeatUuid[] = "6f2a0006-8f4d-4b1a-9f1c-7d19d2a10001";
constexpr char kPodId[] = "BRK-F412FA9FF241";

constexpr int kDefaultCalibrationRssi = -59;
constexpr int kDefaultThresholdRssi = -50;
constexpr unsigned long kBlinkIntervalMs = 500;
constexpr unsigned long kStatusIntervalMs = 5000;
constexpr unsigned long kHeartbeatIntervalMs = 250;

BLEService proximityService(kServiceUuid);
BLEIntCharacteristic calibrationCharacteristic(
    kCalibrationUuid, BLERead | BLEWrite);
BLEIntCharacteristic thresholdCharacteristic(
    kThresholdUuid, BLERead | BLEWrite);
BLEStringCharacteristic versionCharacteristic(kVersionUuid, BLERead, 16);
BLEStringCharacteristic podIdCharacteristic(kPodIdUuid, BLERead, 32);
BLEUnsignedLongCharacteristic heartbeatCharacteristic(
    kHeartbeatUuid, BLERead | BLENotify);

unsigned long lastBlinkAt = 0;
unsigned long lastStatusAt = 0;
unsigned long lastHeartbeatAt = 0;
unsigned long heartbeat = 0;
bool ledOn = false;
bool wasConnected = false;

void printHelp() {
  Serial.println();
  Serial.println("BROKE-RANGE BLE proximity beacon");
  Serial.println("The phone measures this beacon's RSSI.");
  Serial.println();
  Serial.println("Serial commands:");
  Serial.println("  help       Show this help");
  Serial.println("  status     Show BLE and calibration values");
  Serial.println("  cal -62    Set expected RSSI measured at 1 meter");
  Serial.println("  threshold -50  Set the initial lock/unlock threshold");
  Serial.println();
}

void printStatus() {
  Serial.print("BLE address: ");
  Serial.println(BLE.address());
  Serial.print("Advertising name: ");
  Serial.println(kDeviceName);
  Serial.print("Pod ID: ");
  Serial.println(kPodId);
  Serial.print("Calibration RSSI at 1 m: ");
  Serial.print(calibrationCharacteristic.value());
  Serial.println(" dBm");
  Serial.print("Proposed threshold: ");
  Serial.print(thresholdCharacteristic.value());
  Serial.println(" dBm");
  Serial.print("Central connected: ");
  Serial.println(BLE.connected() ? "yes" : "no");
}

void handleSerialCommand() {
  if (!Serial.available()) {
    return;
  }

  String command = Serial.readStringUntil('\n');
  command.trim();
  command.toLowerCase();

  if (command == "help") {
    printHelp();
    return;
  }

  if (command == "status") {
    printStatus();
    return;
  }

  if (command.startsWith("cal ")) {
    const int value = command.substring(4).toInt();
    if (value >= -100 && value <= -20) {
      calibrationCharacteristic.writeValue(value);
      Serial.print("Calibration RSSI set to ");
      Serial.print(value);
      Serial.println(" dBm");
    } else {
      Serial.println("Calibration must be between -100 and -20 dBm.");
    }
    return;
  }

  if (command.startsWith("threshold ")) {
    const int value = command.substring(10).toInt();
    if (value >= -100 && value <= -20) {
      thresholdCharacteristic.writeValue(value);
      Serial.print("Threshold set to ");
      Serial.print(value);
      Serial.println(" dBm");
    } else {
      Serial.println("Threshold must be between -100 and -20 dBm.");
    }
    return;
  }

  if (command.length() > 0) {
    Serial.println("Unknown command. Type 'help'.");
  }
}

void handleBleWrites() {
  if (calibrationCharacteristic.written()) {
    Serial.print("Phone changed calibration RSSI to ");
    Serial.print(calibrationCharacteristic.value());
    Serial.println(" dBm");
  }

  if (thresholdCharacteristic.written()) {
    Serial.print("Phone changed threshold to ");
    Serial.print(thresholdCharacteristic.value());
    Serial.println(" dBm");
  }
}

void updateLed(unsigned long now) {
  const bool connected = BLE.connected();

  if (connected) {
    digitalWrite(LED_BUILTIN, HIGH);
    ledOn = true;
    return;
  }

  if (now - lastBlinkAt >= kBlinkIntervalMs) {
    lastBlinkAt = now;
    ledOn = !ledOn;
    digitalWrite(LED_BUILTIN, ledOn ? HIGH : LOW);
  }
}
}  // namespace

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);

  Serial.begin(115200);
  Serial.setTimeout(50);

  const unsigned long serialWaitStartedAt = millis();
  while (!Serial && millis() - serialWaitStartedAt < 3000) {
  }

  if (!BLE.begin()) {
    Serial.println("BLE startup failed. Reset the UNO R4 WiFi and try again.");
    while (true) {
      digitalWrite(LED_BUILTIN, !digitalRead(LED_BUILTIN));
      delay(100);
    }
  }

  BLE.setDeviceName(kDeviceName);
  BLE.setLocalName(kDeviceName);
  BLE.setAdvertisedService(proximityService);

  proximityService.addCharacteristic(calibrationCharacteristic);
  proximityService.addCharacteristic(thresholdCharacteristic);
  proximityService.addCharacteristic(versionCharacteristic);
  proximityService.addCharacteristic(podIdCharacteristic);
  proximityService.addCharacteristic(heartbeatCharacteristic);
  BLE.addService(proximityService);

  calibrationCharacteristic.writeValue(kDefaultCalibrationRssi);
  thresholdCharacteristic.writeValue(kDefaultThresholdRssi);
  versionCharacteristic.writeValue("1.0.0");
  podIdCharacteristic.writeValue(kPodId);
  heartbeatCharacteristic.writeValue(heartbeat);

  BLE.advertise();

  printHelp();
  printStatus();
  Serial.println("Advertising. Scan for BROKE-RANGE from a BLE scanner.");
}

void loop() {
  BLE.poll();
  handleSerialCommand();
  handleBleWrites();

  const unsigned long now = millis();
  const bool connected = BLE.connected();

  if (connected && now - lastHeartbeatAt >= kHeartbeatIntervalMs) {
    lastHeartbeatAt = now;
    heartbeatCharacteristic.writeValue(++heartbeat);
  }

  if (connected != wasConnected) {
    wasConnected = connected;
    Serial.println(connected ? "Phone connected." : "Phone disconnected.");
  }

  if (now - lastStatusAt >= kStatusIntervalMs) {
    lastStatusAt = now;
    Serial.println(connected ? "BLE connected; LED solid."
                             : "BLE advertising; LED blinking.");
  }

  updateLed(now);
}
