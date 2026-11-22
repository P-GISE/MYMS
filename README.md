# MYMS 실행

## 코드 구조

Xcode와 Swift Playground는 `MYMS.swiftpm/Sources/AppModule` 아래의 같은 소스를 사용합니다.

```text
App/                      앱 시작점 (MYMSApp)
Models/                   운동·기록·난이도, 계정·연령대 모델
Services/                 Supabase 통신, 계정, 운동 저장, Bluetooth·운동 판정
Views/
  WorkoutHome.swift       탭 구성과 공유 화면 상태
  Authentication/         로그인·회원가입과 공통 입력 화면
  Plans/                  운동 계획·편집·안내·동작 애니메이션
  Workout/                실시간 운동·휴식·결과 화면
  History/                운동 기록·메모·삭제 화면
  Settings/               계정 설정·로그아웃·탈퇴 화면
  Shared/                 여러 화면에서 사용하는 연령대 선택기
```

탭별 화면은 `WorkoutHome`의 extension으로 나누어 기존 상태와 동작을 유지합니다.
Swift Playground는 소스 폴더 안의 Swift 파일을 함께 빌드합니다.
새 Swift 파일을 추가하면 Xcode 프로젝트의 소스 목록에도 등록해야 합니다.

## iPad Swift Playground (Mac 없이 실행)

앱의 최소 지원 버전은 iPadOS 17입니다. iPadOS에 맞는 최신 Swift Playground를 설치합니다.
`MYMS.swiftpm`은 iPad에서 여는 앱 프로젝트이며, Xcode 프로젝트도 이 안의 동일한 Swift 소스를 사용합니다.

1. Windows에서 저장소 루트의 `MYMS.swiftpm` 폴더 전체를 ZIP으로 압축합니다. `Package.swift`만 따로 전달하면 실행되지 않습니다.
2. ZIP을 iCloud Drive 또는 사용하는 파일 전송 서비스로 iPad에 전달하고 파일 앱에 저장합니다.
3. 파일 앱에서 ZIP을 풀고 `MYMS.swiftpm`을 Swift Playground로 엽니다. 연결 앱이 표시되지 않으면 Swift Playground의 문서 탐색기에서 해당 프로젝트를 선택합니다.
4. 실행 버튼을 누르고 Bluetooth 권한 요청을 허용합니다. 권한은 `AppInfo.plist`에 선언되어 있습니다. 필요하면 앱 설정의 Capabilities에서 Bluetooth 항목도 확인합니다.
5. 인터넷에 연결한 상태에서 회원가입 또는 로그인하고, 운동 계획을 추가합니다. 운동 안내에서 **이 운동 준비하기**를 선택합니다.
6. 운동 탭에서 **센서 없이 시연**을 켜고 운동을 시작합니다. 시작 거리 측정이 끝나면 **가상 동작 1회**로 횟수와 세트 전환을 확인합니다. 시연 결과는 서버에 저장하지 않습니다.

센서를 사용할 때는 시연을 끄고 Arduino의 전원을 켠 뒤 연결과 거리 수신을 확인합니다.
시연도 현재 앱 구조상 로그인과 Supabase 데이터 로딩이 필요합니다. 서버가 준비되지 않았다면 운동을 시작할 수 없습니다.
Windows에서는 SwiftUI/CoreBluetooth 앱을 빌드할 수 없으므로 최종 컴파일과 센서 동작은 iPad에서 확인해야 합니다.
Swift Playground 안에서 실행하는 구성으로, 홈 화면에 독립 앱을 설치하거나 TestFlight로 배포하는 절차와는 다릅니다.

PowerShell에서 전송용 ZIP 만들기:

```powershell
New-Item -ItemType Directory -Force build | Out-Null
Compress-Archive -LiteralPath MYMS.swiftpm -DestinationPath build/MYMS-Playground.zip -Force
```

수정 후 ZIP을 다시 만들어 전달합니다. iPad에서는 기존 사본과 구분하여 최신 프로젝트를 엽니다.
Swift Playground에서 수정한 코드는 Windows 저장소에 자동 반영되지 않습니다.

참고: [Apple 앱 권한 안내](https://developer.apple.com/documentation/swift-playgrounds/project-capabilities)

## Arduino

Arduino IDE에서 Nano 33 BLE Sense 또는 Sense Rev2에 맞는 보드를 선택합니다.
Library Manager에서 ArduinoBLE, Arduino_APDS9960, VL53L0X by Pololu를 설치합니다.
VL53L0X 모듈을 3.3V, GND, A4(SDA), A5(SCL)에 연결하고 두 센서가 위를 향하도록 배치합니다.
Arduino/MYMS/MYMS.ino를 열어 업로드합니다. 초기화 오류는 115200 baud 시리얼 모니터에서 확인합니다.

## iPhone

MYMS.xcodeproj를 열고 MYMS 타깃의 Signing & Capabilities에서 Team을 설정합니다.
실제 iPhone을 실행 대상으로 선택하고 Run을 누릅니다. 앱의 Bluetooth 권한을 허용합니다.

센서가 연결되면 시작 버튼 또는 오른쪽 스와이프로 운동을 시작하고, 가슴을 센서 위에 둔 채 화면이 운동 중으로 바뀔 때까지 시작 자세를 유지합니다.
운동 계획 탭에서 푸시업, 스쿼트, 힙 브리지, 앉아서 무릎 들기 중 하나를 고르고 난이도, 목표 횟수, 세트 수, 휴식 시간을 설정합니다. 기본 푸시업 계획은 중급 깊이 50%, 10회씩 3세트, 휴식 30초입니다. 스쿼트, 힙 브리지, 앉아서 무릎 들기의 센서 배치와 판정 기준은 실측으로 확인해야 합니다. 힙 브리지와 앉아서 무릎 들기는 센서를 측정 부위 위에 단단히 고정해 아래를 향하게 합니다. 기존 계정에는 운동 계획의 추가 버튼으로 새 운동을 등록합니다.
왼쪽 스와이프는 일시정지, 오른쪽은 재개, 일시정지 중 아래 스와이프는 종료, 휴식 중 위 스와이프는 다음 세트를 시작합니다.

## 기록과 포인트

유효 횟수가 있는 세션은 완료하거나 종료할 때 Supabase에 저장됩니다. 기록 화면에서 결과를 조회하고 메모를 편집하거나 기록을 삭제할 수 있습니다.
초급·중급·상급는 유효 1회당 각각 1·2·3점, 목표를 채운 세트는 추가 5점입니다. 일일 한도는 300점이며, 기록을 삭제하면 그 기록의 포인트도 차감됩니다.

## 계정

이메일, 8자 이상의 비밀번호, 연령대를 입력해 가입합니다. 인증 메일이 발송되면 메일에서 주소를 확인한 뒤 로그인합니다.
로그인 상태는 기기의 Keychain에 저장되어 앱을 다시 열어도 유지되고, 로그아웃하거나 탈퇴하면 지워집니다. 서버에서 로그인이 만료되면 로그인 화면으로 돌아갑니다.
설정에서 로그아웃하거나 비밀번호를 다시 입력해 Supabase 계정과 운동 데이터를 삭제할 수 있습니다.
이전 로컬 계정과 운동 데이터는 서버 계정으로 자동 이전되지 않습니다.

기존 계정은 설정에서 연령대를 입력할 수 있습니다. 운동 계획의 추천은 운동 종류, 연령대, 선택한 운동 경험을 반영하며, 적용 후에도 횟수와 세트를 편집할 수 있습니다.

## 센서 없이 시연

운동 계획에서 운동을 고른 뒤 운동 탭에서 **센서 없이 시연**을 켭니다.
운동 시작 후 시작 거리 측정이 끝나면 **가상 동작 1회**를 눌러 횟수를 확인합니다.
목표에 도달하면 다음 세트 또는 결과 화면으로 이어집니다. 시연에서는 기록과 포인트가 저장되지 않습니다.

## Supabase

새 프로젝트를 구성할 때는 `supabase/migrations`의 SQL을 파일명 순서대로 적용합니다. 앱의 프로젝트 URL과 공개 API 키는 `MYMSCloud`에 설정합니다.
