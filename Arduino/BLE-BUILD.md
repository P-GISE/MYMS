# Nano 33 BLE 동시 통신 빌드

검증 구성: Arduino Nano 33 BLE Sense Rev2, arduino:mbed_nano 4.6.0, ArduinoBLE 2.1.1, Windows BLE 검사. 스케치의 센서 UUID와 10Hz 전송 주기는 바꾸지 않습니다.

## 빌드·업로드

저장소 루트 PowerShell에서 실행합니다.

```powershell
.\Arduino\build-and-upload.ps1 -Upload -Port COM5
```

컴파일만 하려면 -Upload를 생략합니다. Arduino IDE/ArduinoBLE 설치 위치가 다르면 -ArduinoCli 및 -ArduinoBLE 경로 인수를 지정합니다. 다른 버전 HCI 소스에는 자동 보정을 적용하지 않고 오류로 중단합니다.

이 스크립트는 설치된 ArduinoBLE를 수정하지 않습니다. build/arduino-libraries에 사본을 만들고, 확인한 HCI.cpp에만 수정 후 --library 옵션으로 선택합니다. 빌드 산출물은 build/arduino-firmware입니다. Arduino IDE의 기본 업로드만 사용하면 이 보정이 적용되지 않습니다.

## 확인한 문제와 보정

Windows 동시 알림/읽기/LED 검사에서 읽기 시간 초과를 재현했습니다. HCI 로그에는 실제 연결 핸들0의 ACL TX1195개에 대해 연결되지 않은 핸들4 완료898개까지 합산되는 현상이 있습니다. ArduinoBLE는 완료 이벤트의 핸들을 무시하여 전송 잔량을 너무 빨리 줄입니다. 읽기 응답과 알림은 같은 송신 경로를 공유합니다.

프로젝트 사본에서는 활성 ATT 연결이 아닌 핸들의 완료 이벤트와 0개 완료 이벤트를 무시합니다. 마지막 연결 해제 시 pending 카운터를 비워 재연결에 이전 잔량이 남지 않게 합니다. 핸들4 이벤트의 생성 원인 자체는 아직 확정하지 않았습니다. 이 보정은 검증한 Nano33 단일 연결 구성의 우회 수정이며 모든 보드/드라이버 문제의 해결을 뜻하지 않습니다.

## 재현 검사

Tests/README.md의 Windows 의존성을 준비한 뒤 다음을 실행합니다. 다른 iPad의 연결은 먼저 해제합니다.

```powershell
python Tests/ble/ble_runtime_check.py concurrent all_notify_and_read 3
python Tests/ble/ble_runtime_check.py control all_notify_and_led 3
python Tests/ble/hardware_identity_check.py
```

수정 전 동시 통신은 17회 읽기 후 시간 초과였습니다. 최종 비재진입 보정 빌드에서 동시 읽기·알림 3회와 LED 반복 제어 3회가 모두 통과했습니다. 매 회 재연결했으며 총 234회 읽기에 성공했습니다. 고유 ID 재연결 검사도 2회 통과했습니다. 초기 후보 빌드의 통과와 최종 빌드 검사는 구분합니다. iOS Swift 빌드와 실제 iPad 화면/장시간 무선 안정성은 별도 확인이 필요합니다.
