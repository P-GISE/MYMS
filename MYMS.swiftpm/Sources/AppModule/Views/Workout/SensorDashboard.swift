import SwiftUI
import Charts

struct SensorDashboard: View {
    @ObservedObject var coach: Coach

    var body: some View {
        NavigationStack {
            List {
                Section("Bluetooth") {
                    SensorConnectionCard(coach: coach)
                    Text("거리 센서 없이도 내장 센서를 확인할 수 있습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("운동 측정 설정") {
            Picker("측정 방식", selection: Binding(
                get: { coach.measurementMode },
                set: { coach.setMeasurementMode($0) }
            )) {
                ForEach(Coach.MeasurementMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .disabled(!coach.canSelect || coach.isSimulating)
            if coach.measurementMode == .acceleration {
                Text("보드를 손에 들고 움직여 코치 흐름을 시험합니다. 고정된 보드로 사람의 운동을 측정할 수 없으며, 이 기록에는 포인트가 적립되지 않습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if coach.canSelect || coach.isSimulating {
                Toggle("센서 없이 시연", isOn: Binding(
                    get: { coach.isSimulating },
                    set: { coach.setSimulation($0) }
                ))
                .disabled(!coach.canSelect)
            }

                }
                Section("IMU · 최근 10초") {
                    LabeledContent("가속도 크기", value: formatted(coach.acceleration, unit: "g"))
                    if coach.accelerationHistory.isEmpty {
                        ContentUnavailableView("가속도 수신 대기", systemImage: "waveform.path.ecg",
                                               description: Text("보드를 연결한 후 움직여 변화를 확인하세요."))
                    } else {
                        Chart(coach.accelerationHistory) { sample in
                            LineMark(x: .value("시간", sample.date), y: .value("가속도", sample.magnitude))
                        }
                        .chartYAxisLabel("g")
                        .frame(height: 180)
                        .accessibilityLabel("최근 가속도 이력 그래프")
                    }
                    Text("정지 상태는 약 1g입니다. 보드를 기울이기만 하면 크기 변화는 작을 수 있습니다. 운동 시험은 운동 탭의 IMU 동작 테스트에서 진행하세요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("밝기") {
                    LabeledContent("밝기 원시값", value: formatted(coach.environment.brightnessRaw, unit: "count"))
                    LabeledContent("밝기 비교", value: coach.environment.brightnessDescription)
                    LabeledContent("저장된 기준값", value: formatted(coach.environment.brightnessReference, unit: "count"))
                    Button("현재 밝기를 기준으로 설정") { coach.calibrateBrightness() }
                        .disabled(!coach.canCalibrateBrightness)
                    Text("센서 앞을 가리지 않고, 비교 기준으로 삼을 밝은 환경에서 설정하세요. 원시값은 조도(lux)가 아니며, 기준값의 25% 이하를 ‘기준보다 어두움’으로 표시합니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("바닥 경사") {
                    LabeledContent("기준면과의 각도", value: formatted(coach.environment.inclineDegrees, unit: "°"))
                    LabeledContent("경사 비교", value: coach.environment.inclineDescription)
                    Button("수평 기준 보정") { coach.calibrateFloor() }
                        .disabled(!coach.canCalibrateFloor)
                    if coach.isCalibratingFloor {
                        ProgressView("수평 기준 측정 중 · 움직이지 마세요", value: coach.floorCalibrationProgress)
                    }
                    Text("수평이 확인된 안정적인 면에 보드를 놓고 보정하세요. 보정 후 운동할 바닥에 보드를 같은 면으로 놓고 2초 이상 정지시키세요. 손에 들거나 움직일 때의 각도는 바닥 경사가 아닙니다. 3° 이하 구분은 초기 비교 기준입니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("재연결하면 밝기와 수평 기준을 다시 설정하세요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("직접 선택하는 환경") {
                    Picker("운동기구", selection: $coach.equipment) {
                        ForEach(WorkoutEquipment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("장소", selection: $coach.place) {
                        ForEach(WorkoutPlace.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("신발", selection: $coach.footwear) {
                        ForEach(WorkoutFootwear.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Text("밝기·경사와 선택한 환경은 운동 시작 시 기록에 담습니다. 운동 중에는 선택을 변경할 수 없습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .disabled(!coach.canSelect)
                Section("손 제스처와 제어") {
                    LabeledContent("최근 방향", value: coach.lastGesture)
                    LabeledContent("근접 버튼", value: coach.proximityPressed ? "눌림" : "대기")
                    Toggle("보드 LED", isOn: Binding(get: { coach.ledOn }, set: { coach.setLED($0) }))
                        .disabled(!coach.canControlLED)
                    if let error = coach.deviceError { Text(error).foregroundStyle(.red) }
                    Text("오른쪽: 시작·재개 / 왼쪽: 일시정지 / 위: 다음 세트 / 아래: 일시정지 중 종료. 유효한 측정값이 있어야 운동을 시작할 수 있습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("센서")
        }
    }

    private func formatted(_ value: Double?, unit: String) -> String {
        value.map { "\($0.formatted(.number.precision(.fractionLength(2)))) \(unit)" } ?? "미수신"
    }
}

struct SensorConnectionCard: View {
    @ObservedObject var coach: Coach
    @State private var choosingDevice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if coach.isSimulating {
                Label("시연 모드 · 가상 센서", systemImage: "waveform")
                    .font(.headline)
                Text("실제 보드의 연결 상태와 관계없이 가상 측정값을 사용합니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    if isBusy {
                        ProgressView().accessibilityLabel(title)
                    } else {
                        Image(systemName: statusIcon).foregroundStyle(statusColor)
                            .font(.title2)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.headline).foregroundStyle(statusColor)
                        Text(coach.connection).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                if let device = coach.selectedDevice {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).font(.subheadline.bold())
                        if let hardwareID = coach.verifiedHardwareID {
                            Text("아두이노 ID · \(hardwareID)")
                                .font(.subheadline.monospaced()).textSelection(.enabled)
                            Label("보드 고유 ID 읽기 완료", systemImage: "checkmark.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if let hardwareID = device.hardwareID {
                            Text("아두이노 ID · \(hardwareID)")
                                .font(.subheadline.monospaced()).textSelection(.enabled)
                            Text("선택한 보드 ID · 연결 후 재확인")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("연결 후 보드 ID 확인")
                                .font(.subheadline).foregroundStyle(.orange)
                        }
                        if let received = coach.lastSensorDataAt {
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                (Text("마지막 유효 측정값 · ")
                                 + Text(received, style: .relative)
                                 + Text(" 전"))
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("아직 유효한 측정값을 받지 못했습니다.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if coach.connected, coach.measurementMode == .distance, coach.latestDistance == nil {
                    Text("거리 센서가 없다면 ‘IMU 동작 테스트’를 선택해 내장 센서 수신을 확인하세요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack { connectionActions }
                    VStack(alignment: .leading) { connectionActions }
                }

                if coach.connected {
                    Toggle("보드 LED로 실물 확인", isOn: Binding(
                        get: { coach.ledOn }, set: { coach.setLED($0) }
                    ))
                    .disabled(!coach.canControlLED)
                    .font(.subheadline)
                    Text(coach.canControlLED
                         ? "스위치를 바꾼 뒤 내 보드의 LED가 바뀌는지 확인하세요. 표시 상태는 보드 응답 후 갱신됩니다."
                         : "이 기기는 LED 확인 기능을 제공하지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = coach.deviceError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Text("아두이노 ID로 보드를 구분합니다. 처음 연결할 때는 LED도 켜서 내 보드가 맞는지 확인하세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .sheet(isPresented: $choosingDevice) { devicePicker }
    }

    @ViewBuilder
    private var connectionActions: some View {
        Button {
            choosingDevice = true
        } label: {
            Label(coach.selectedDevice == nil ? "기기 선택" : "다른 기기 선택", systemImage: "list.bullet")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!coach.canChooseDevice)
        if coach.selectedDevice != nil {
            if !coach.connected, !isBusy, let device = coach.selectedDevice {
                Button("다시 연결") { coach.connectDevice(device.id) }
                    .buttonStyle(.bordered)
                    .disabled(!coach.canChooseDevice)
            }
            Button("연결 해제", role: .destructive) { coach.disconnectDevice() }
                .buttonStyle(.bordered)
        } else {
            Button("다시 검색") { coach.refreshDevices() }
                .buttonStyle(.bordered)
                .disabled(!coach.canChooseDevice || coach.isSearchingDevices)
        }
    }

    private var devicePicker: some View {
        NavigationStack {
            List {
                Section {
                    if coach.isSearchingDevices {
                        ProgressView("주변 MYMS 기기 검색 중")
                    }
                    if coach.discoveredDevices.isEmpty {
                        ContentUnavailableView("아직 검색된 기기가 없습니다", systemImage: "antenna.radiowaves.left.and.right.slash",
                            description: Text("보드 전원을 확인하고 가까이 두세요. 다른 iPad에 연결돼 있다면 그쪽 연결을 먼저 해제하세요."))
                    }
                    ForEach(coach.discoveredDevices) { device in
                        Button {
                            coach.connectDevice(device.id)
                            choosingDevice = false
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(device.name).font(.headline).foregroundStyle(.primary)
                                if let hardwareID = device.hardwareID {
                                    Text("아두이노 ID · \(hardwareID)")
                                        .font(.subheadline.monospaced()).foregroundStyle(.primary)
                                } else {
                                    Text("연결 후 보드 ID 확인")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                                Text("검색 시 신호 · \(device.rssi) dBm")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .disabled(!coach.canChooseDevice)
                    }
                } footer: {
                    Text("선택하면 보드 고유 ID를 직접 읽고, 광고 또는 이전에 확인한 ID와 비교합니다. 같은 이름이어도 ID를 확인하고, LED로 실물을 구분하세요.")
                }
            }
            .navigationTitle("센서 선택")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { choosingDevice = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("다시 검색") { coach.refreshDevices() }
                        .disabled(!coach.canChooseDevice || coach.isSearchingDevices)
                }
            }
            .onAppear { coach.refreshDevices() }
        }
    }

    private var isBusy: Bool {
        switch coach.connectionStage {
        case .searching, .connecting: return true
        case .verifying: return !coach.connected
        default: return false
        }
    }

    private var title: String {
        switch coach.connectionStage {
        case .unavailable: return "Bluetooth 확인 필요"
        case .searching: return "주변 기기 검색 중"
        case .waiting: return "연결 대기 중"
        case .connecting: return "기기에 연결 중"
        case .verifying: return coach.connected ? "연결 완료 · 측정값 대기" : "센서 확인 중"
        case .receiving: return "측정 데이터 수신 중"
        case .stale: return "측정 데이터 수신 대기"
        case .failed: return "연결하지 못했습니다"
        }
    }

    private var statusIcon: String {
        switch coach.connectionStage {
        case .receiving: return "checkmark.circle.fill"
        case .unavailable, .failed, .stale: return "exclamationmark.circle"
        default: return "antenna.radiowaves.left.and.right"
        }
    }

    private var statusColor: Color {
        switch coach.connectionStage {
        case .receiving: return .green
        case .unavailable, .failed, .stale: return .orange
        default: return .primary
        }
    }
}
