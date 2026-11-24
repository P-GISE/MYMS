import SwiftUI
import Charts

struct SensorDashboard: View {
    @ObservedObject var coach: Coach
    let showWorkout: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 800 && !typeSize.isAccessibilitySize
                let layout = wide
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                ScrollView {
                    layout {
                        VStack(alignment: .leading, spacing: 16) {
                            SensorConnectionCard(coach: coach)
                            measurementSettings
                        }
                        .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 16) {
                            accelerationPanel
                            calibrationPanel
                            environmentPanel
                            boardControls
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: 1180)
                    .padding(wide ? 24 : 16)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(MYMSStyle.canvas)
            .navigationTitle("센서")
        }
    }

    private var measurementSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            sensorHeading("운동 측정", icon: "waveform.path.ecg")
            LabeledContent("측정 방식") {
                Picker("측정 방식", selection: Binding(
                    get: { coach.measurementMode }, set: { coach.setMeasurementMode($0) }
                )) {
                    ForEach(Coach.MeasurementMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(!coach.canSelect || coach.isSimulating)
            }
            if coach.measurementMode == .acceleration {
                sensorHint("보드를 손에 들고 움직여 동작을 시험하세요. 고정된 보드로는 운동을 측정할 수 없습니다. IMU 테스트는 포인트를 지급하지 않습니다.")
            }
            if coach.canSelect || coach.isSimulating {
                Divider()
                Toggle("센서 없이 시연", isOn: Binding(
                    get: { coach.isSimulating }, set: { coach.setSimulation($0) }
                ))
                .disabled(!coach.canSelect)
                if coach.isSimulating {
                    sensorHint("운동 탭에서 가상 동작을 입력할 수 있습니다. 종료한 시연은 이 기기의 기록에 남습니다.")
                }
            }
            if coach.canStartWorkout {
                Button(action: showWorkout) {
                    Label("운동 화면으로 이동", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .mymsPrimaryButton()
                .controlSize(.large)
            }
        }
        .padding(18)
        .mymsCard()
    }

    private var accelerationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sensorHeading("가속도", icon: "waveform")
            LabeledContent("최근 10초", value: formatted(coach.acceleration, unit: "g"))
                .monospacedDigit()
            if coach.accelerationHistory.isEmpty {
                Label("보드를 연결하면 측정값을 표시합니다.", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background(MYMSStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
            } else {
                Chart(coach.accelerationHistory) { sample in
                    LineMark(x: .value("시간", sample.date), y: .value("가속도", sample.magnitude))
                        .foregroundStyle(MYMSStyle.accent)
                }
                .chartYAxisLabel("g")
                .frame(height: 140)
                .accessibilityLabel("최근 10초의 가속도 변화")
            }
            sensorHint("정지 상태는 약 1g입니다. 보드를 기울이기만 하면 변화가 작을 수 있습니다.")
        }
        .padding(18)
        .mymsCard()
    }

    private var calibrationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sensorHeading("환경 센서 보정", icon: "slider.horizontal.3")
            DisclosureGroup("밝기") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("밝기 원시값", value: formatted(coach.environment.brightnessRaw, unit: "count"))
                    LabeledContent("저장된 기준값", value: formatted(coach.environment.brightnessReference, unit: "count"))
                    LabeledContent("밝기 비교", value: coach.environment.brightnessDescription)
                    sensorHint("센서 앞을 가리지 말고 밝은 곳에서 설정하세요. 원시값은 조도(lux)가 아니며, 기준의 25% 이하면 ‘기준보다 어두움’으로 표시합니다.")
                    Button("현재 밝기를 기준으로 설정") { coach.calibrateBrightness() }
                        .buttonStyle(.bordered)
                        .disabled(!coach.canCalibrateBrightness)
                }.padding(.vertical, 8)
            }
            Divider()
            DisclosureGroup("바닥 경사") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("기준면과의 각도", value: formatted(coach.environment.inclineDegrees, unit: "°"))
                    LabeledContent("경사 비교", value: coach.environment.inclineDescription)
                    sensorHint("수평면에서 보정한 뒤 운동할 바닥에 보드를 같은 면으로 놓고 2초 이상 기다리세요. 손에 들거나 움직일 때는 바닥 경사를 측정할 수 없습니다. 초기 구분 기준은 3°입니다.")
                    Button("수평 기준 보정") { coach.calibrateFloor() }
                        .buttonStyle(.bordered)
                        .disabled(!coach.canCalibrateFloor)
                    if coach.isCalibratingFloor {
                        ProgressView("수평 기준 측정 중 · 움직이지 마세요", value: coach.floorCalibrationProgress)
                    }
                }.padding(.vertical, 8)
            }
            sensorHint("보드를 다시 연결하면 밝기와 수평 기준을 다시 설정하세요.")
        }
        .padding(18)
        .mymsCard()
    }

    private var environmentPanel: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("운동기구") {
                    Picker("운동기구", selection: $coach.equipment) {
                        ForEach(WorkoutEquipment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                LabeledContent("장소") {
                    Picker("장소", selection: $coach.place) {
                        ForEach(WorkoutPlace.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                LabeledContent("신발") {
                    Picker("신발", selection: $coach.footwear) {
                        ForEach(WorkoutFootwear.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                sensorHint("선택한 환경은 운동 시작 시 기록됩니다. 운동 중에는 바꿀 수 없습니다.")
            }
            .pickerStyle(.menu)
            .disabled(!coach.canSelect)
            .padding(.top, 12)
        } label: {
            sensorHeading("운동 환경", icon: "mappin.and.ellipse")
        }
        .padding(18)
        .mymsCard()
    }

    private var boardControls: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("최근 방향", value: coach.lastGesture)
                LabeledContent("근접 버튼", value: coach.proximityPressed ? "눌림" : "대기")
                if coach.isSimulating && coach.connected {
                    Toggle("보드 LED", isOn: Binding(get: { coach.ledOn }, set: { coach.setLED($0) }))
                        .disabled(!coach.canControlLED)
                    if let error = coach.deviceError { Text(error).foregroundStyle(.red) }
                }
                sensorHint("오른쪽은 시작·재개, 왼쪽은 일시정지, 위쪽은 다음 세트입니다. 일시정지 중 아래쪽으로 움직이면 운동을 종료합니다.")
            }
            .padding(.top, 12)
        } label: {
            sensorHeading("보드 제스처", icon: "hand.raised")
        }
        .padding(18)
        .mymsCard()
    }

    private func sensorHeading(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
    }

    private func sensorHint(_ message: String) -> some View {
        Text(message).font(.footnote).foregroundStyle(.secondary)
    }

    private func formatted(_ value: Double?, unit: String) -> String {
        value.map { "\($0.formatted(.number.precision(.fractionLength(2)))) \(unit)" } ?? "미수신"
    }
}

struct SensorConnectionCard: View {
    @ObservedObject var coach: Coach
    @State private var choosingDevice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("보드 연결", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline).accessibilityAddTraits(.isHeader)
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
                        Image(systemName: statusIcon)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(statusColor)
                            .frame(width: 44, height: 44)
                            .background(MYMSStyle.canvas, in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.title3.bold())
                        Text(coach.connection).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                if let device = coach.selectedDevice {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).font(.subheadline.bold())
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
                Text("보드가 여러 대라면 LED를 켜서 내 기기를 확인하세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .mymsCard()
        .sheet(isPresented: $choosingDevice) { devicePicker }
    }

    @ViewBuilder
    private var connectionActions: some View {
        Button {
            choosingDevice = true
        } label: {
            Label(coach.selectedDevice == nil ? "기기 선택" : "다른 기기 선택", systemImage: "list.bullet")
        }
        .mymsPrimaryButton()
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
                    Text("연결할 MYMS를 선택하세요. 같은 이름의 보드가 여러 대면 연결 후 LED로 구분할 수 있습니다.")
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
        case .receiving: return MYMSStyle.accent
        case .unavailable, .failed, .stale: return .orange
        default: return .primary
        }
    }
}
