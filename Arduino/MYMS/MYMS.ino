#include <ArduinoBLE.h>
#include <Arduino_APDS9960.h>
#include <Arduino_BMI270_BMM150.h>
#include <VL53L0X.h>
#include <Wire.h>
#include <math.h>
#include <nrf.h>

BLEService fitness("19B10000-E8F2-537E-4F6C-D104768A1214");
BLEFloatCharacteristic acceleration("19B10001-E8F2-537E-4F6C-D104768A1214", BLERead | BLENotify);
BLEByteCharacteristic button("19B10002-E8F2-537E-4F6C-D104768A1214", BLERead | BLENotify);
BLEByteCharacteristic led("19B10003-E8F2-537E-4F6C-D104768A1214", BLERead | BLEWrite);
BLECharacteristic distance("19B10004-E8F2-537E-4F6C-D104768A1214", BLERead | BLENotify, 2, true);
BLECharacteristic gesture("19B10005-E8F2-537E-4F6C-D104768A1214", BLENotify, 2, true);
BLEFloatCharacteristic brightness("19B10009-E8F2-537E-4F6C-D104768A1214", BLERead | BLENotify);
BLECharacteristic accelerationVector("19B1000A-E8F2-537E-4F6C-D104768A1214", BLERead | BLENotify, 12, true);
BLECharacteristic deviceIdentity("19B1000B-E8F2-537E-4F6C-D104768A1214", BLERead, 16, true);
char hardwareID[17];
char advertisedName[22];
VL53L0X tof;
bool distanceAvailable = false;
bool gestureAvailable = false;
bool imuAvailable = false;
bool buttonPressed = false;
uint8_t ledState = 0;
float accelerationG = NAN;
float accelerationAxes[3] = {NAN, NAN, NAN};
float clearCounts = NAN;
unsigned long lastAcceleration = 0;
unsigned long lastColor = 0;
uint8_t sequence = 0;
unsigned long lastSample = 0;
unsigned long lastReport = 0;

void setup() {
  Serial.begin(115200);
  Wire.begin();
  tof.setTimeout(50);
  // A missing optional distance sensor must not prevent BLE advertising.
  distanceAvailable = tof.init();
  if (distanceAvailable) tof.startContinuous(100);
  else Serial.println("VL53L0X unavailable: BLE only, distance=0");
  gestureAvailable = APDS.begin();
  if (!gestureAvailable) Serial.println("APDS9960 initialization failed");
  imuAvailable = IMU.begin();
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);
  if (!BLE.begin()) {
    while (true) {
      Serial.println("BLE initialization failed");
      delay(1000);
    }
  }
  // FICR identifies the physical nRF52840 across firmware uploads.
  snprintf(hardwareID, sizeof(hardwareID), "%08lX%08lX",
           static_cast<unsigned long>(NRF_FICR->DEVICEID[1]),
           static_cast<unsigned long>(NRF_FICR->DEVICEID[0]));
  snprintf(advertisedName, sizeof(advertisedName), "MYMS-%s", hardwareID);
  BLE.setLocalName(advertisedName);
  BLE.setAdvertisedService(fitness);
  fitness.addCharacteristic(acceleration);
  fitness.addCharacteristic(button);
  fitness.addCharacteristic(led);
  fitness.addCharacteristic(distance);
  fitness.addCharacteristic(gesture);
  fitness.addCharacteristic(brightness);
  fitness.addCharacteristic(accelerationVector);
  fitness.addCharacteristic(deviceIdentity);
  BLE.addService(fitness);
  deviceIdentity.writeValue(reinterpret_cast<const uint8_t *>(hardwareID), 16);
  Serial.print("arduino_id=");
  Serial.println(hardwareID);
  acceleration.writeValue(NAN);
  brightness.writeValue(NAN);
  accelerationVector.writeValue(reinterpret_cast<const uint8_t *>(accelerationAxes), sizeof(accelerationAxes));
  button.writeValue(255);
  led.writeValue(ledState);
  const uint8_t noDistance[] = {0, 0};
  distance.writeValue(noDistance, sizeof(noDistance));
  BLE.advertise();
}

void loop() {
  BLE.poll();
  if (led.written()) {
    const uint8_t requested = led.value();
    if (requested <= 1) {
      ledState = requested;
      digitalWrite(LED_BUILTIN, ledState ? HIGH : LOW);
    }
    led.writeValue(ledState);
    Serial.print("led=");
    Serial.println(ledState);
  }
  if (millis() - lastSample >= 100) {
    lastSample = millis();
    if (imuAvailable && IMU.accelerationAvailable()) {
      float x, y, z;
      if (IMU.readAcceleration(x, y, z) && isfinite(x) && isfinite(y) && isfinite(z)) {
        lastAcceleration = millis();
        accelerationAxes[0] = x;
        accelerationAxes[1] = y;
        accelerationAxes[2] = z;
        accelerationG = sqrtf(x * x + y * y + z * z);
      }
    }
    if (!imuAvailable || millis() - lastAcceleration > 500) {
      accelerationG = NAN;
      accelerationAxes[0] = accelerationAxes[1] = accelerationAxes[2] = NAN;
    }
    acceleration.writeValue(accelerationG);
    // Nano 33 BLE uses IEEE 754 float32 in little-endian order.
    accelerationVector.writeValue(reinterpret_cast<const uint8_t *>(accelerationAxes), sizeof(accelerationAxes));
    if (gestureAvailable && APDS.colorAvailable()) {
      int red, green, blue, clear;
      if (APDS.readColor(red, green, blue, clear) && clear >= 0 && clear <= 65535) {
        clearCounts = static_cast<float>(clear);
        lastColor = millis();
      }
    }
    if (gestureAvailable && APDS.proximityAvailable()) {
      const int proximity = APDS.readProximity();
      if (proximity >= 0) {
        // shortcut: initial near/far thresholds; calibrate with the final enclosure.
        if (proximity < 50) buttonPressed = true;
        else if (proximity > 80) buttonPressed = false;
        button.writeValue(buttonPressed ? 1 : 0);
      }
    }
    uint16_t mm = 0;
    if (distanceAvailable) {
      mm = tof.readRangeContinuousMillimeters();
      if (tof.timeoutOccurred() || mm > 2000) mm = 0;
    }
    const uint8_t payload[] = {uint8_t(mm), uint8_t(mm >> 8)};
    distance.writeValue(payload, sizeof(payload));
    if (millis() - lastReport >= 1000) {
      lastReport = millis();
      if (!gestureAvailable || millis() - lastColor > 1500) clearCounts = NAN;
      brightness.writeValue(clearCounts);
      Serial.print("accel_g=");
      Serial.print(accelerationG, 4);
      Serial.print(" imu=");
      Serial.print(imuAvailable ? "OK" : "MISSING");
      Serial.print(" accel_xyz_g=");
      Serial.print(accelerationAxes[0], 4);
      Serial.print(",");
      Serial.print(accelerationAxes[1], 4);
      Serial.print(",");
      Serial.print(accelerationAxes[2], 4);
      Serial.print(" brightness_clear=");
      Serial.print(clearCounts, 0);
      Serial.print(" ");
      Serial.print("distance_mm=");
      Serial.print(mm);
      Serial.print(" distance_sensor=");
      Serial.print(distanceAvailable ? "OK" : "MISSING");
      Serial.print(" gesture_sensor=");
      Serial.print(gestureAvailable ? "OK" : "FAILED");
      Serial.print(" ble_connected=");
      Serial.println(BLE.connected() ? "YES" : "NO");
    }
  }

  if (!gestureAvailable || !APDS.gestureAvailable()) return;
  uint8_t direction;
  switch (APDS.readGesture()) {
    case GESTURE_UP: direction = 1; break;
    case GESTURE_DOWN: direction = 2; break;
    case GESTURE_LEFT: direction = 3; break;
    case GESTURE_RIGHT: direction = 4; break;
    default: return;
  }
  const uint8_t payload[] = {direction, ++sequence};
  gesture.writeValue(payload, sizeof(payload));
  Serial.print("gesture=");
  Serial.println(direction);
}
