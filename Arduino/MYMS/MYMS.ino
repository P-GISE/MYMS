#include <ArduinoBLE.h>
#include <Arduino_APDS9960.h>
#include <VL53L0X.h>
#include <Wire.h>

BLEService fitness("19B10000-E8F2-537E-4F6C-D104768A1214");
BLECharacteristic distance("19B10004-E8F2-537E-4F6C-D104768A1214", BLERead | BLENotify, 2, true);
BLECharacteristic gesture("19B10005-E8F2-537E-4F6C-D104768A1214", BLENotify, 2, true);
VL53L0X tof;
bool gestureAvailable = false;
uint8_t sequence = 0;
unsigned long lastSample = 0;

void setup() {
  Serial.begin(115200);
  Wire.begin();
  tof.setTimeout(50);
  if (!tof.init()) {
    Serial.println("VL53L0X initialization failed");
    while (true) { delay(1000); }
  }
  tof.startContinuous(100);
  gestureAvailable = APDS.begin();
  if (!gestureAvailable) Serial.println("APDS9960 initialization failed");
  if (!BLE.begin()) {
    Serial.println("BLE initialization failed");
    while (true) { delay(1000); }
  }
  BLE.setLocalName("SmartFitnessCoach");
  BLE.setAdvertisedService(fitness);
  fitness.addCharacteristic(distance);
  fitness.addCharacteristic(gesture);
  BLE.addService(fitness);
  BLE.advertise();
}

void loop() {
  BLE.poll();
  if (millis() - lastSample >= 100) {
    lastSample = millis();
    uint16_t mm = tof.readRangeContinuousMillimeters();
    if (tof.timeoutOccurred() || mm > 2000) mm = 0;
    const uint8_t payload[] = {uint8_t(mm), uint8_t(mm >> 8)};
    distance.writeValue(payload, sizeof(payload));
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
}
