# Swift 자체 검사

각 파일은 별도 실행 파일입니다. Swift Playground 앱 소스에는 포함하지 않습니다.
Windows 환경에는 Swift/iOS SDK가 없어 아래 Swift 검사를 실행하지 못했습니다. Swift 5.9 이상이 있는 Mac에서 저장소 루트에서 실행합니다.

```sh
mkdir -p build
swiftc MYMS.swiftpm/Sources/AppModule/Models/SensorData.swift Tests/SensorDataChecks.swift -o build/sensor-checks
./build/sensor-checks

swiftc -target "$(uname -m)-apple-macosx14.0" \
  MYMS.swiftpm/Sources/AppModule/Models/*.swift \
  MYMS.swiftpm/Sources/AppModule/Services/MYMSCloud.swift \
  MYMS.swiftpm/Sources/AppModule/Services/Accounts.swift \
  MYMS.swiftpm/Sources/AppModule/Services/WorkoutStore.swift \
  MYMS.swiftpm/Sources/AppModule/Views/History/WorkoutStatisticsView.swift \
  Tests/LocalHistoryChecks.swift -o build/history-checks
./build/history-checks

swiftc -target "$(uname -m)-apple-macosx14.0" \
  MYMS.swiftpm/Sources/AppModule/Models/*.swift \
  MYMS.swiftpm/Sources/AppModule/Services/MYMSCloud.swift \
  MYMS.swiftpm/Sources/AppModule/Services/Accounts.swift \
  MYMS.swiftpm/Sources/AppModule/Services/WorkoutStore.swift \
  Tests/WorkoutRecoveryChecks.swift -o build/recovery-checks
./build/recovery-checks
```

센서 검사는 리틀 엔디언 Float·3축 패킷·길이 오류·NaN·무한대·범위 밖 입력, IMU 반복/복귀/최소 간격, 2초 안정 구간, 30° 벡터 각도, 환경 선택 저장 및 이전 형식 디코딩을 확인합니다.
기록 검사는 임시 UUID 계정으로 저장·새 저장소 인스턴스에서 복구·환경값·계정 격리·삭제·주간 합계·연속일·PR 및 테스트 기록 제외를 확인하고 임시 계정 파일을 정리합니다.
저장소 인스턴스 재생성 검사는 실제 iPad 앱 강제 종료·재실행 시험을 대신하지 않습니다.
복구 검사는 진행 단계별 재생성, 잘못된 체크포인트 거부, 실제 쓰기 실패와 롤백·재시도, 중복 완료·삭제 후 재완료 거부, 일일 한도, 이전 파일 형식과 손상 파일 보존을 확인합니다.

## iPad에서 확인할 복구 시나리오

1. 로컬 모드에서 실제 IMU 동작 테스트를 시작하고 2회 이상 센 뒤 앱을 완전히 종료합니다. 같은 프로젝트·로컬 모드로 다시 열어 복구하면 같은 횟수로 일시정지 상태여야 합니다.
2. Arduino 전원을 껐다 켭니다. 다시 연결돼도 자동으로 카운트하지 않고 명시적으로 재개해야 합니다. IMU가 안정된 뒤 새 동작부터 세는지 확인합니다.
3. 목표를 채워 휴식 중 앱을 종료·재실행합니다. 남은 휴식이 그대로 표시되고 직접 재개/다음 세트를 눌러야 합니다.
4. 운동 종료를 여러 번 시도하거나 종료 직후 앱을 재실행해 같은 세션 기록이 하나인지 확인합니다. IMU 테스트는 포인트 0이며, ToF 포인트 시험은 실제 거리 센서가 있을 때 진행합니다.
5. 미완료 진행 기록을 버린 후 재실행하면 복구 카드가 없어야 합니다. 다른 계정의 진행 상태는 표시되면 안 됩니다.

Windows에서는 위 iPad 시나리오와 Swift 검사를 실행하지 못했습니다. 자동 검사 파일은 별도 실행 파일이므로 함께 한 번에 컴파일하지 않습니다.

## Windows 실물 BLE 재현 검사

Windows 11, Python 3.12 이상, 실제 Nano 33 연결이 필요합니다. 다른 BLE 클라이언트는 연결을 해제합니다.
아래 검사는 실제 LED를 켜고 끄며, 연결을 종료할 때 Windows 연결 옵션도 해제합니다.

```powershell
uv pip install --python 3.12 --target build/ble-check-deps bleak anyio
python Tests/ble/ble_runtime_check.py notify-only notify_only 2
python Tests/ble/ble_runtime_check.py concurrent-io all_notify_and_read 2
python Tests/ble/ble_runtime_check.py led-control all_notify_and_led 2
```

결과는 `build/ble-debug/<첫 번째 인수>.json`에 기록됩니다. `notify_only`는 알림 수신, `all_notify_and_read`는 알림 중 센서 읽기·LED 제어, `all_notify_and_led`는 알림 중 LED 제어입니다.
기본 ArduinoBLE에서는 전체 알림 중 읽기·쓰기 시간 초과가 재현됐습니다. 현재 보정 빌드와 검증 결과는 [Arduino/BLE-BUILD.md](../Arduino/BLE-BUILD.md)를 참고하세요. 먼저 해당 빌드·업로드를 수행한 뒤 검사합니다. 실패 결과도 그대로 보존합니다.
필요하면 마지막 인수에 `throughput`을 추가해 Windows의 전송량 우선 요청과 실제 연결 주기를 기록할 수 있습니다. 15ms 연결에서도 오류가 재현돼 해결책으로 간주하지 않습니다.
## 센서 연결 화면 수동 확인

Windows에서는 SwiftUI 빌드 및 실제 화면 검증을 수행하지 못했습니다. iPad에서 다음을 확인하세요.

1. Bluetooth를 끄거나 권한을 거부하면 검색 중 대신 원인 안내가 표시됩니다.
2. 기기 선택 목록에서 이름·아두이노 고유 ID·신호를 비교하고 직접 선택합니다. 같은 이름의 보드가 있어도 첫 기기에 자동 연결하지 않습니다.
3. 연결 중 → 센서 확인 중 → 측정값 대기 → 실제 데이터 수신 중을 구분합니다. 거리 센서가 없으면 거리 모드가 녹색 수신 상태가 되지 않아야 합니다. IMU 모드에서는 유효한 가속도로 수신 상태를 확인합니다.
4. LED 스위치를 조작하고 해당 보드 LED가 실제로 변하는지 확인합니다. 고유 ID 대조는 기기 구분용이며 암호화된 소유자 인증은 아닙니다.
5. 기기 목록을 열고 취소해도 현재 운동·연결이 유지됩니다. 다른 기기를 실제 선택하면 운동은 일시정지되어야 합니다.
6. 보드 전원 차단 또는 측정 중단 시 정상 표시가 해제됩니다. 진행 기록을 유지한 채 다시 연결하고 명시적으로 운동을 재개합니다.
7. 시연 모드는 가상 센서로 표시됩니다. 큰 글자·가로/세로·VoiceOver에서 기기 목록과 버튼을 확인합니다.


`ConnectionStatusChecks.swift`는 연결 상태의 시간 경계·잘못된 시각과 ID 길이·ASCII 16진수 형식을 검사합니다. iOS 테스트용 실행 타깃에 AppModule 소스(기존 MYMSApp의 @main 제외)와 함께 포함해 실행해야 합니다. Windows에서는 실행하지 않았습니다.
고유 ID 실기기 검사는 Windows에서 `uv pip install --target build/ble-check-deps bleak anyio`로 준비한 뒤 `python Tests/ble/hardware_identity_check.py`를 실행합니다. 다른 중앙 기기의 연결을 해제해야 합니다. 스캔 응답 이름이 수신되지 않으면 광고 ID 대조는 생략하고 보드에서 읽은 고유 ID를 확인합니다.

추가 디버깅 회귀 확인: BLE 연결을 유지한 채 선택한 측정값을 끊거나 거리 0을 보내면 정상 수신 표시가 해제되고, 휴식 중에도 남은 휴식·운동 시간이 멈춰야 합니다. 데이터가 돌아와도 사용자가 재개하기 전 자동으로 이어지면 안 됩니다. 네트워크 동기화만 실패했을 때는 진행 중 운동·기기 저장 오류가 없는 상태에서 로그아웃할 수 있어야 합니다. 이 시나리오의 iPad 실행은 아직 수행하지 않았습니다.
