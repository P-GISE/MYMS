import Foundation
import Combine
import CoreBluetooth

final class Coach: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum MeasurementMode: String, CaseIterable {
        case distance = "ToF 거리", acceleration = "IMU 동작 테스트"
    }
    enum ConnectionStage: Equatable {
        case unavailable, searching, waiting, connecting, verifying, receiving, stale, failed

        static func measurement(_ lastSample: TimeInterval?, _ now: TimeInterval) -> Self {
            guard let lastSample else { return .verifying }
            let age = now - lastSample
            return age.isFinite && (0...2).contains(age) ? .receiving : .stale
        }
    }

    struct SensorDevice: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
        let hardwareID: String?
    }

    enum Phase: String {
        case ready = "대기", calibrating = "시작 자세를 유지하세요", training = "운동 중"
        case paused = "일시정지", resting = "휴식", finished = "운동 종료"
    }

    @Published private(set) var phase = Phase.ready
    @Published private(set) var connection = "Bluetooth 준비 중"
    @Published private(set) var connected = false
    @Published private(set) var connectionStage = ConnectionStage.unavailable
    @Published private(set) var discoveredDevices: [SensorDevice] = []
    @Published private(set) var selectedDevice: SensorDevice?
    @Published private(set) var lastSensorDataAt: Date?
    @Published private(set) var verifiedHardwareID: String?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var scanTimer: Timer?
    private var pendingDeviceID: UUID?
    private var cancellingPeripheral: CBPeripheral?
    private var rememberedHardwareIDs: [UUID: String] = [:]
    @Published private(set) var isSearchingDevices = false
    var canChooseDevice: Bool {
        central?.state == .poweredOn && !handshakeActive && pendingDeviceID == nil && cancellingPeripheral == nil
    }
    private var validDistanceAt: TimeInterval?
    private var validAccelerationAt: TimeInterval?
    private var distanceDate: Date?
    private var accelerationDate: Date?
    @Published private(set) var reps = 0
    @Published private(set) var set = 1
    @Published private(set) var restSeconds = 30
    @Published private(set) var restInterrupted = false
    @Published private(set) var shallow = false
    @Published private(set) var workout = Workout()
    @Published private(set) var result: WorkoutRecord?
    @Published private(set) var summary: WorkoutRecord?
    @Published private(set) var latestDistance: Double?
    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var isSimulating = false
    @Published private(set) var isSimulatingRep = false
    @Published private(set) var measurementMode = MeasurementMode.distance
    @Published private(set) var acceleration: Double?
    @Published private(set) var accelerationHistory: [AccelerationSample] = []
    @Published private(set) var environment = SensorEnvironment(measuredAt: Date())
    @Published var equipment = WorkoutEquipment.unspecified
    @Published var place = WorkoutPlace.unspecified
    @Published var footwear = WorkoutFootwear.unspecified
    @Published private(set) var floorCalibrationProgress = 0.0
    @Published private(set) var isCalibratingFloor = false
    private var floorReference: GravityVector?
    private var gravity: GravityVector?
    private var floorWindow = StableGravityWindow()
    private var sessionEnvironment: SensorEnvironment?
    @Published private(set) var recoveryCandidate: WorkoutProgress?
    @Published private(set) var persistenceError: String?
    var onCheckpoint: ((WorkoutProgress) -> Bool)?
    var onComplete: ((WorkoutRecord) -> Bool)?
    var onDiscard: (() -> Bool)?
    private var sessionID: UUID?
    private var pendingCompletion: WorkoutRecord?
    private var elapsedAccumulated = 0.0
    private var clockBegan: TimeInterval?
    private var progressTimer: Timer?
    @Published private(set) var lastGesture = "입력 대기"
    @Published private(set) var proximityPressed = false
    @Published private(set) var ledOn = false
    @Published private(set) var deviceError: String?
    private var receivedAt: [String: TimeInterval] = [:]
    private var accelerationCounter = AccelerationCounter()
    private var ledCharacteristic: CBCharacteristic?
    private var connectionTimer: Timer?
    private var handshakeActive = false
    private var awaitingInitialLED = false
    private var awaitingIdentity = false
    private var notificationQueue: [CBCharacteristic] = []
    private var lastGestureSequence: UInt8?
    var recordingAvailable = false

    var canControlLED: Bool { connected && ledCharacteristic != nil }
    var canCalibrateBrightness: Bool { canSelect && connected && (environment.brightnessRaw ?? 0) > 0 }
    var canCalibrateFloor: Bool { canSelect && connected && gravity != nil && !isCalibratingFloor }

    func calibrateBrightness() {
        guard canCalibrateBrightness else { return }
        environment.brightnessReference = environment.brightnessRaw
    }

    func calibrateFloor() {
        guard canCalibrateFloor else { return }
        floorReference = nil
        environment.inclineDegrees = nil
        floorWindow = StableGravityWindow()
        floorCalibrationProgress = 0
        isCalibratingFloor = true
    }
    private var simulationTimer: Timer?
    private var simulationSample = 0
    private var lastLiveSample: TimeInterval?
    private var distanceTimer: Timer?

    var canMeasure: Bool {
        guard persistenceError == nil, recoveryCandidate == nil else { return false }
        if isSimulating { return latestDistance != nil }
        let last = measurementMode == .distance ? validDistanceAt : validAccelerationAt
        return connected && ConnectionStage.measurement(last, ProcessInfo.processInfo.systemUptime) == .receiving
            && (measurementMode == .distance ? latestDistance != nil : acceleration != nil)
    }

    func setMeasurementMode(_ mode: MeasurementMode) {
        guard canSelect else { return }
        measurementMode = mode
        resetMotion()
        updateConnectionStatus()
    }

    func setLED(_ enabled: Bool) {
        guard connected, let sensor, let ledCharacteristic else { return }
        sensor.writeValue(Data([enabled ? 1 : 0]), for: ledCharacteristic, type: .withResponse)
    }

    func setSimulation(_ enabled: Bool) {
        guard canSelect, enabled != isSimulating else { return }
        isSimulating = enabled
        phase = .ready
        reps = 0
        set = 1
        summary = nil
        resetMotion()
        latestDistance = nil
        if enabled {
            measure(400)
            simulationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.feedSimulation()
            }
        } else {
            simulationTimer?.invalidate()
            simulationTimer = nil
        }
    }

    func simulateRep() {
        guard isSimulating, phase == .training, !isSimulatingRep else { return }
        simulationSample = 0
        isSimulatingRep = true
    }

    private func feedSimulation() {
        guard isSimulating else { return }
        if isSimulatingRep && phase == .training {
            simulationSample += 1
            let depth = workout.exercise.depth(for: workout.level) + 0.05
            measure(simulationSample <= 8 ? 400 * (1 - depth) : 400)
            if simulationSample >= 12 { isSimulatingRep = false }
        } else {
            isSimulatingRep = false
            measure(400)
        }
    }
    private var sessionStart = Date()
    private var totalReps = 0
    private var completedSets = 0

    var canSelect: Bool { (phase == .ready || phase == .finished) && recoveryCandidate == nil && sessionID == nil }

    func select(_ plan: Workout) {
        guard canSelect, plan.isValid else { return }
        workout = plan
        reps = 0
        set = 1
        phase = .ready
    }

    func finish() {
        guard phase != .ready, phase != .finished, recoveryCandidate == nil else { return }
        restTimer?.invalidate()
        stopClock()
        resetMotion()
        if totalReps == 0 {
            guard isSimulating || onDiscard?() == true else { persistenceFailed(); return }
            sessionID = nil
            persistenceError = nil
            phase = .finished
            return
        }
        let completionID: UUID
        if let sessionID { completionID = sessionID }
        else if isSimulating { completionID = UUID() }
        else { persistenceFailed(); return }
        let completed = pendingCompletion ?? WorkoutRecord(id: completionID, workout: workout,
                               reps: totalReps, sets: completedSets, seconds: elapsedSeconds,
                               points: measurementMode == .acceleration ? 0 : totalReps * workout.level.rawValue + completedSets * 5,
                               environment: sessionEnvironment,
                               measurementSource: measurementMode.rawValue)
        if !isSimulating {
            pendingCompletion = completed
            guard onComplete?(completed) == true else { persistenceFailed(); return }
        }
        pendingCompletion = nil
        sessionID = nil
        persistenceError = nil
        phase = .finished
        summary = completed
        if !isSimulating { result = completed }
    }

    func offerRecovery(_ progress: WorkoutProgress) {
        guard canSelect, progress.isValid else { return }
        if isSimulating { setSimulation(false) }
        recoveryCandidate = progress
    }

    @discardableResult
    func restoreRecovery() -> Bool {
        guard let saved = recoveryCandidate, saved.isValid else { return false }
        let restored = WorkoutProgress(id: saved.id, workout: saved.workout, startedAt: saved.startedAt,
                                       elapsedSeconds: saved.elapsedSeconds, reps: saved.reps, set: saved.set,
                                       totalReps: saved.totalReps, completedSets: saved.completedSets,
                                       restSeconds: saved.restSeconds,
                                       phase: saved.phase == .resting ? .resting : .paused,
                                       measurementSource: saved.measurementSource, environment: saved.environment,
                                       updatedAt: Date())
        guard onCheckpoint?(restored) == true else {
            persistenceError = "중단된 운동을 복구하지 못했습니다. 저장 오류를 확인하고 다시 시도하세요."
            return false
        }
        workout = saved.workout
        sessionID = saved.id
        sessionStart = saved.startedAt
        elapsedAccumulated = Double(saved.elapsedSeconds)
        clockBegan = nil
        reps = saved.reps
        set = saved.set
        totalReps = saved.totalReps
        completedSets = saved.completedSets
        restSeconds = saved.restSeconds
        restInterrupted = saved.phase == .resting
        measurementMode = MeasurementMode(rawValue: saved.measurementSource) ?? .distance
        updateConnectionStatus()
        sessionEnvironment = saved.environment
        equipment = saved.environment?.equipment ?? .unspecified
        place = saved.environment?.place ?? .unspecified
        footwear = saved.environment?.footwear ?? .unspecified
        resetMotion()
        phase = saved.phase == .resting ? .resting : .paused
        summary = nil
        result = nil
        pendingCompletion = nil
        recoveryCandidate = nil
        persistenceError = nil
        return true
    }

    @discardableResult
    func discardRecovery() -> Bool {
        guard recoveryCandidate != nil else { return false }
        guard onDiscard?() == true else {
            persistenceError = "진행 기록을 삭제하지 못했습니다. 저장 오류를 확인하고 다시 시도하세요."
            return false
        }
        recoveryCandidate = nil
        persistenceError = nil
        return true
    }

    @discardableResult
    func retryPersistence() -> Bool {
        if recoveryCandidate != nil { persistenceError = nil; return true }
        if pendingCompletion != nil { finish(); return pendingCompletion == nil }
        return checkpoint()
    }

    func suspendForBackground() {
        if phase == .resting { pauseForConnectionLoss() }
        else { pause() }
    }

    func resumeRest() {
        expireTelemetry()
        guard phase == .resting, restInterrupted, canMeasure else { return }
        guard restSeconds > 0 else { gesture(1); return }
        restInterrupted = false
        restDeadline = Date().addingTimeInterval(Double(restSeconds))
        startClock()
        scheduleRestTimer()
        checkpoint()
    }

    private func scheduleRestTimer() {
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.restSeconds = max(0, Int(ceil(self.restDeadline.timeIntervalSinceNow)))
            if self.restSeconds == 0 { self.gesture(1) }
        }
    }

    private var elapsedSeconds: Int {
        let running = clockBegan.map { max(0, ProcessInfo.processInfo.systemUptime - $0) } ?? 0
        return max(0, Int(elapsedAccumulated + running))
    }

    private func startClock() {
        if clockBegan == nil { clockBegan = ProcessInfo.processInfo.systemUptime }
    }

    private func stopClock() {
        if let began = clockBegan { elapsedAccumulated += max(0, ProcessInfo.processInfo.systemUptime - began) }
        clockBegan = nil
    }

    @discardableResult
    private func checkpoint() -> Bool {
        guard !isSimulating, let sessionID else { return true }
        guard pendingCompletion == nil else { return false }
        let savedPhase: WorkoutProgress.Phase
        switch phase {
        case .calibrating: savedPhase = .calibrating
        case .training: savedPhase = .training
        case .paused: savedPhase = .paused
        case .resting: savedPhase = .resting
        case .ready, .finished: return true
        }
        let progress = WorkoutProgress(id: sessionID, workout: workout, startedAt: sessionStart,
                                       elapsedSeconds: elapsedSeconds, reps: reps, set: set, totalReps: totalReps,
                                       completedSets: completedSets, restSeconds: min(workout.rest, restSeconds),
                                       phase: savedPhase, measurementSource: measurementMode.rawValue,
                                       environment: sessionEnvironment, updatedAt: Date())
        guard progress.isValid, onCheckpoint?(progress) == true else { persistenceFailed(); return false }
        persistenceError = nil
        return true
    }

    private func persistenceFailed() {
        restTimer?.invalidate()
        stopClock()
        resetMotion()
        if phase == .resting { restInterrupted = true }
        else { phase = .paused }
        persistenceError = "진행 상태를 저장하지 못해 운동을 멈췄습니다. 앱을 닫지 말고 저장을 다시 시도하세요."
    }

    private let suffix = "-E8F2-537E-4F6C-D104768A1214"
    private lazy var service = CBUUID(string: "19B10000" + suffix)
    private lazy var distance = CBUUID(string: "19B10004" + suffix)
    private lazy var gestureID = CBUUID(string: "19B10005" + suffix)
    private lazy var accelerationID = CBUUID(string: "19B10001" + suffix)
    private lazy var buttonID = CBUUID(string: "19B10002" + suffix)
    private lazy var ledID = CBUUID(string: "19B10003" + suffix)
    private lazy var brightnessID = CBUUID(string: "19B10009" + suffix)
    private lazy var gravityID = CBUUID(string: "19B1000A" + suffix)
    private lazy var hardwareIdentityID = CBUUID(string: "19B1000B" + suffix)
    private var central: CBCentralManager!
    private var sensor: CBPeripheral?
    private var samples: [Double] = []
    private var calibration: [Double] = []
    private var calibrationStart: TimeInterval?
    private var baseline = 0.0
    private var descent: TimeInterval?
    private var reachedDepth = false
    private var restDeadline = Date.distantPast
    private var restTimer: Timer?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        distanceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.expireTelemetry()
            self.updateConnectionStatus()
            if !self.isSimulating, let last = self.lastLiveSample,
               ProcessInfo.processInfo.systemUptime - last > 1 {
                self.lastLiveSample = nil
                self.measure(0)
                if self.measurementMode == .distance { self.pauseForConnectionLoss() }
            }
        }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.clockBegan != nil else { return }
            self.checkpoint()
        }
    }

    deinit {
        simulationTimer?.invalidate()
        distanceTimer?.invalidate()
        restTimer?.invalidate()
        connectionTimer?.invalidate()
        progressTimer?.invalidate()
        scanTimer?.invalidate()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            connected = false
            pendingDeviceID = nil
            cancellingPeripheral = nil
            isSearchingDevices = false
            scanTimer?.invalidate()
            discoveredDevices.removeAll()
            discoveredPeripherals.removeAll()
            connectionTimer?.invalidate()
            sensor?.delegate = nil
            sensor = nil
            clearTelemetry()
            if !isSimulating { pauseForConnectionLoss() }
            if !isSimulating { measure(0) }
            connectionStage = .unavailable
            switch central.state {
            case .poweredOff: connection = "Bluetooth를 켜 주세요"
            case .unauthorized: connection = "설정에서 MYMS의 Bluetooth 권한을 허용해 주세요"
            case .unsupported: connection = "이 기기는 Bluetooth LE를 지원하지 않습니다"
            default: connection = "Bluetooth 준비 중"
            }
            return
        }
        scan()
    }

    func stopConnection() {
        pendingDeviceID = nil
        cancellingPeripheral = nil
        suspendForBackground()
        simulationTimer?.invalidate()
        distanceTimer?.invalidate()
        connectionTimer?.invalidate()
        restTimer?.invalidate()
        progressTimer?.invalidate()
        central.stopScan()
        isSearchingDevices = false
        scanTimer?.invalidate()
        if let sensor { central.cancelPeripheralConnection(sensor) }
        sensor?.delegate = nil
        sensor = nil
        connected = false
        resetHandshake()
        connectionStage = .waiting
        connection = "연결 대기 중"
        central.delegate = nil
    }

    func refreshDevices() {
        guard !handshakeActive, pendingDeviceID == nil, cancellingPeripheral == nil else { return }
        guard central.state == .poweredOn else {
            centralManagerDidUpdateState(central)
            return
        }
        deviceError = nil
        let previous = selectedDevice.flatMap { discoveredPeripherals[$0.id] }
        discoveredDevices.removeAll()
        discoveredPeripherals.removeAll()
        if let previous { discoveredPeripherals[previous.identifier] = previous }
        scan()
    }

    private func scan() {
        guard canChooseDevice else { return }
        scanTimer?.invalidate()
        if sensor == nil {
            connectionStage = .searching
            connection = "주변 MYMS 기기를 검색하고 있습니다"
        }
        isSearchingDevices = true
        central.scanForPeripherals(withServices: [service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        scanTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.central.stopScan()
            self.isSearchingDevices = false
            guard self.sensor == nil else { return }
            self.connectionStage = .waiting
            self.connection = self.discoveredDevices.isEmpty
                ? "기기를 찾지 못했습니다. 보드 전원과 다른 iPad의 연결을 확인하세요"
                : "연결할 기기를 선택하세요"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard central.isScanning else { return }
        let previous = discoveredDevices.first { $0.id == peripheral.identifier }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? previous?.name ?? peripheral.name ?? "이름 없는 MYMS 기기"
        let advertisedID = (name.hasPrefix("MYMS-") ? Self.parseHardwareID(String(name.dropFirst(5))) : nil)
            ?? previous?.hardwareID ?? rememberedHardwareIDs[peripheral.identifier]
        let device = SensorDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue,
                                  hardwareID: advertisedID)
        discoveredPeripherals[device.id] = peripheral
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
        }
    }

    func connectDevice(_ id: UUID) {
        guard canChooseDevice,
              let device = discoveredDevices.first(where: { $0.id == id })
                ?? selectedDevice.flatMap({ $0.id == id ? $0 : nil }) else { return }
        guard let peripheral = discoveredPeripherals[id]
                ?? central.retrievePeripherals(withIdentifiers: [id]).first else {
            connectionStage = .failed
            connection = "기기 정보를 찾지 못했습니다. 다시 검색해 주세요"
            return
        }
        discoveredPeripherals[id] = peripheral
        guard sensor?.identifier != id else { return }
        if let previous = sensor {
            if !isSimulating { pauseForConnectionLoss() }
            pendingDeviceID = id
            connected = false
            verifiedHardwareID = nil
            central.stopScan()
            isSearchingDevices = false
            scanTimer?.invalidate()
            connectionStage = .connecting
            connection = "기존 연결을 종료하고 선택한 기기로 변경 중"
            cancelConnection(previous)
            return
        }
        central.stopScan()
        isSearchingDevices = false
        scanTimer?.invalidate()
        if !isSimulating { pauseForConnectionLoss() }
        clearTelemetry()
        selectedDevice = device
        sensor = peripheral
        peripheral.delegate = self
        handshakeActive = true
        connectionStage = .connecting
        connection = "선택한 기기에 연결 중"
        central.connect(peripheral)
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            guard let self, self.sensor === peripheral, self.handshakeActive else { return }
            self.failHandshake("센서 연결 초기화 시간이 초과되었습니다.", peripheral: peripheral)
        }
    }

    func disconnectDevice() {
        guard sensor != nil || cancellingPeripheral == nil else { return }
        pendingDeviceID = nil
        if !isSimulating { pauseForConnectionLoss() }
        connectionTimer?.invalidate()
        let previous = sensor
        sensor?.delegate = nil
        sensor = nil
        connected = false
        selectedDevice = nil
        clearTelemetry()
        if !isSimulating { measure(0) }
        if let previous {
            connectionStage = .connecting
            connection = "기기 연결을 종료하는 중"
            cancelConnection(previous)
        } else if cancellingPeripheral == nil {
            refreshDevices()
        }
    }

    private func updateConnectionStatus() {
        guard connected else { return }
        let last = measurementMode == .distance ? validDistanceAt : validAccelerationAt
        lastSensorDataAt = measurementMode == .distance ? distanceDate : accelerationDate
        connectionStage = ConnectionStage.measurement(last, ProcessInfo.processInfo.systemUptime)
        switch connectionStage {
        case .receiving: connection = "실제 측정 데이터 수신 중"
        case .stale: connection = "측정 데이터가 끊겼습니다. 보드 상태를 확인하세요"
        default:
            connection = measurementMode == .distance
                ? "BLE 연결 완료 · 유효한 거리값 대기 중. 거리 센서가 없으면 IMU 모드를 선택하세요"
                : "BLE 연결 완료 · 유효한 IMU 측정값 대기 중"
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === sensor, handshakeActive else { return }
        connectionStage = .verifying
        connection = "MYMS 서비스와 센서 알림을 확인 중"
        peripheral.discoverServices([service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if peripheral === cancellingPeripheral {
            centralManager(central, didDisconnectPeripheral: peripheral, error: error)
            return
        }
        guard peripheral === sensor else { return }
        connectionTimer?.invalidate()
        let failure = deviceError ?? error?.localizedDescription ?? "센서에 연결하지 못했습니다."
        peripheral.delegate = nil
        sensor = nil
        connected = false
        clearTelemetry()
        deviceError = failure
        connectionStage = .failed
        connection = failure
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral === cancellingPeripheral {
            cancellingPeripheral = nil
            connectionTimer?.invalidate()
            if peripheral !== sensor {
                refreshDevices()
                return
            }
        }
        guard peripheral === sensor else { return }
        connected = false
        connectionTimer?.invalidate()
        let failure = deviceError ?? error?.localizedDescription
        peripheral.delegate = nil
        sensor = nil
        clearTelemetry()
        deviceError = failure
        if !isSimulating { pauseForConnectionLoss() }
        if !isSimulating { measure(0) }
        if let next = pendingDeviceID {
            pendingDeviceID = nil
            connectDevice(next)
        } else {
            connectionStage = .failed
            connection = failure ?? "연결이 끊겼습니다. 기기를 다시 선택하세요"
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === sensor, handshakeActive else { return }
        if let error {
            failHandshake("센서 서비스 검색 실패: \(error.localizedDescription)", peripheral: peripheral)
            return
        }
        guard let fitness = peripheral.services?.first(where: { $0.uuid == service }) else {
            failHandshake("MYMS 센서 서비스를 찾지 못했습니다.", peripheral: peripheral)
            return
        }
        peripheral.discoverCharacteristics([distance, gestureID, accelerationID, buttonID, ledID,
                                            brightnessID, gravityID, hardwareIdentityID], for: fitness)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === sensor, service.uuid == self.service, handshakeActive else { return }
        if let error {
            failHandshake("센서 항목 검색 실패: \(error.localizedDescription)", peripheral: peripheral)
            return
        }
        let characteristics = service.characteristics ?? []
        guard characteristics.contains(where: { $0.uuid == distance }) else {
            failHandshake("거리 측정 항목을 찾지 못했습니다.", peripheral: peripheral)
            return
        }
        let streamIDs = [distance, accelerationID, gestureID, buttonID, brightnessID, gravityID]
        let streams = streamIDs.compactMap { uuid in characteristics.first { $0.uuid == uuid } }
        for characteristic in streams where !characteristic.properties.contains(.notify) {
            if characteristic.uuid == distance || characteristic.uuid == accelerationID {
                failHandshake("필수 센서 알림을 지원하지 않습니다: \(characteristic.uuid.uuidString)", peripheral: peripheral)
                return
            }
            deviceError = "센서 알림을 지원하지 않습니다: \(characteristic.uuid.uuidString)"
        }
        notificationQueue = streams.filter { $0.properties.contains(.notify) }
        ledCharacteristic = characteristics.first { $0.uuid == ledID }
        guard let identity = characteristics.first(where: { $0.uuid == hardwareIdentityID }),
              identity.properties.contains(.read) else {
            failHandshake("기기 고유 ID를 읽을 수 없습니다. 아두이노 펌웨어를 업데이트하세요.", peripheral: peripheral)
            return
        }
        awaitingIdentity = true
        peripheral.readValue(for: identity)
    }

    static func parseHardwareID(_ text: String) -> String? {
        let bytes = Array(text.utf8)
        guard bytes.count == 16,
              bytes.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            return nil
        }
        return text.uppercased()
    }

    static func matchesHardwareID(_ identity: String, advertised: String?, remembered: String?) -> Bool {
        (advertised == nil || advertised == identity) && (remembered == nil || remembered == identity)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === sensor, characteristic.service?.uuid == service else { return }
        guard handshakeActive || connected else { return }
        if handshakeActive {
            guard !awaitingIdentity, !awaitingInitialLED, notificationQueue.first === characteristic else { return }
            notificationQueue.removeFirst()
        }
        if error != nil || !characteristic.isNotifying {
            let message = "센서 알림 수신 실패: \(characteristic.uuid.uuidString)"
            if characteristic.uuid == distance || characteristic.uuid == accelerationID {
                failHandshake(message, peripheral: peripheral)
                return
            }
            deviceError = message
        }
        if handshakeActive { subscribeNext(on: peripheral) }
    }

    private func subscribeNext(on peripheral: CBPeripheral) {
        guard peripheral === sensor, handshakeActive, !awaitingIdentity, !awaitingInitialLED else { return }
        if let characteristic = notificationQueue.first {
            peripheral.setNotifyValue(true, for: characteristic)
        } else {
            let streams = peripheral.services?.first { $0.uuid == service }?.characteristics ?? []
            guard verifiedHardwareID != nil,
                  streams.contains(where: { $0.uuid == distance && $0.isNotifying }),
                  streams.filter({ $0.uuid == accelerationID }).allSatisfy({ $0.isNotifying }) else {
                failHandshake("필수 센서 알림 구독이 완료되지 않았습니다.", peripheral: peripheral)
                return
            }
            handshakeActive = false
            connected = true
            connectionTimer?.invalidate()
            updateConnectionStatus()
        }
    }

    private func failHandshake(_ message: String, peripheral: CBPeripheral) {
        guard peripheral === sensor else { return }
        connected = false
        verifiedHardwareID = nil
        resetHandshake()
        connectionTimer?.invalidate()
        deviceError = message
        connectionStage = .failed
        connection = "센서 연결 실패"
        if !isSimulating { pauseForConnectionLoss() }
        cancelConnection(peripheral)
    }

    private func cancelConnection(_ peripheral: CBPeripheral) {
        cancellingPeripheral = peripheral
        connectionTimer?.invalidate()
        central.cancelPeripheralConnection(peripheral)
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            guard let self, self.cancellingPeripheral === peripheral else { return }
            self.pendingDeviceID = nil
            self.connectionStage = .failed
            self.connection = "연결 종료가 지연됩니다. Bluetooth를 껐다 켠 뒤 다시 연결하세요"
        }
    }

    private func resetHandshake() {
        handshakeActive = false
        awaitingInitialLED = false
        awaitingIdentity = false
        notificationQueue.removeAll()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === sensor, characteristic.service?.uuid == service else { return }
        guard handshakeActive || connected else { return }
        if characteristic.uuid == hardwareIdentityID {
            guard handshakeActive, awaitingIdentity else { return }
            guard error == nil, let data = characteristic.value,
                  let text = String(data: data, encoding: .ascii),
                  let identity = Self.parseHardwareID(text) else {
                failHandshake("기기 고유 ID 응답이 올바르지 않습니다.", peripheral: peripheral)
                return
            }
            // Scan responses may be absent; the board's readable ID is authoritative.
            if !Self.matchesHardwareID(identity, advertised: selectedDevice?.hardwareID,
                                       remembered: rememberedHardwareIDs[peripheral.identifier]) {
                failHandshake("선택한 기기의 ID와 실제 보드 ID가 다릅니다. 연결을 중단합니다.", peripheral: peripheral)
                return
            }
            verifiedHardwareID = identity
            rememberedHardwareIDs[peripheral.identifier] = identity
            if let device = selectedDevice {
                selectedDevice = SensorDevice(id: device.id, name: device.name, rssi: device.rssi, hardwareID: identity)
            }
            awaitingIdentity = false
            if let ledCharacteristic, ledCharacteristic.properties.contains(.read) {
                awaitingInitialLED = true
                peripheral.readValue(for: ledCharacteristic)
            } else {
                subscribeNext(on: peripheral)
            }
            return
        }
        if characteristic.uuid == ledID {
            let completesInitialRead = awaitingInitialLED
            defer {
                if completesInitialRead {
                    awaitingInitialLED = false
                    subscribeNext(on: peripheral)
                }
            }
            if let error {
                deviceError = "LED 상태 읽기 실패: \(error.localizedDescription)"
            } else if let data = characteristic.value, data.count == 1, let value = data.first, value <= 1 {
                ledOn = value == 1
            } else {
                deviceError = "LED 상태 응답이 올바르지 않습니다."
            }
            return
        }
        guard error == nil, let data = characteristic.value else { return }
        let bytes = Array(data)
        if characteristic.uuid == distance {
            guard !isSimulating else { return }
            lastLiveSample = ProcessInfo.processInfo.systemUptime
            let millimeters = SensorPayload.distanceMillimeters(data) ?? 0
            if millimeters > 0 {
                validDistanceAt = lastLiveSample
                distanceDate = Date()
            } else {
                validDistanceAt = nil
            }
            measure(millimeters)
            updateConnectionStatus()
        } else if characteristic.uuid == gestureID {
            guard data.count == 2, (1...4).contains(bytes[0]) else { return }
            guard lastGestureSequence != bytes[1] else { return }
            lastGestureSequence = bytes[1]
            lastGesture = ["위", "아래", "왼쪽", "오른쪽"][Int(bytes[0]) - 1]
            gesture(bytes[0])
        } else if characteristic.uuid == accelerationID {
            guard let value = SensorPayload.float32(data, in: 0...32) else { return }
            receivedAt["acceleration"] = ProcessInfo.processInfo.systemUptime
            acceleration = value
            validAccelerationAt = ProcessInfo.processInfo.systemUptime
            accelerationDate = Date()
            updateConnectionStatus()
            accelerationHistory.append(AccelerationSample(date: Date(), magnitude: value))
            if accelerationHistory.count > 100 { accelerationHistory.removeFirst(accelerationHistory.count - 100) }
            if !isSimulating, measurementMode == .acceleration, phase == .training,
               accelerationCounter.observe(value, at: ProcessInfo.processInfo.systemUptime) { countRep() }
        } else if characteristic.uuid == buttonID {
            guard data.count == 1, bytes[0] <= 1 else { return }
            proximityPressed = bytes[0] == 1
            receivedAt["button"] = ProcessInfo.processInfo.systemUptime
        } else {
            updateEnvironment(characteristic.uuid, data: data)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === sensor, characteristic.service?.uuid == service,
              characteristic.uuid == ledID, connected else { return }
        if let error { deviceError = "LED 변경 실패: \(error.localizedDescription)" }
        if error == nil { peripheral.readValue(for: characteristic) }
    }

    private func updateEnvironment(_ uuid: CBUUID, data: Data) {
        switch uuid {
        case brightnessID:
            environment.brightnessRaw = SensorPayload.float32(data, in: 0...65535)
            receivedAt["brightness"] = ProcessInfo.processInfo.systemUptime
            environment.measuredAt = Date()
        case gravityID:
            let now = ProcessInfo.processInfo.systemUptime
            receivedAt["gravity"] = now
            gravity = SensorPayload.gravity(data)
            guard let gravity else {
                environment.inclineDegrees = nil
                floorWindow = StableGravityWindow()
                floorCalibrationProgress = 0
                isCalibratingFloor = false
                return
            }
            let stable = floorWindow.observe(gravity, at: now)
            if isCalibratingFloor { floorCalibrationProgress = floorWindow.progress }
            guard let stable else {
                environment.inclineDegrees = nil
                return
            }
            if isCalibratingFloor {
                floorReference = stable
                isCalibratingFloor = false
            }
            if let floorReference {
                environment.inclineDegrees = floorReference.angle(to: stable)
                environment.measuredAt = Date()
            }
        default: return
        }
    }

    private func expireTelemetry() {
        let now = ProcessInfo.processInfo.systemUptime
        if let last = receivedAt["acceleration"], now - last > 2 {
            acceleration = nil
        }
        if let last = receivedAt["button"], now - last > 2 { proximityPressed = false }
        if let last = receivedAt["brightness"], now - last > 3 { environment.brightnessRaw = nil }
        if let last = receivedAt["gravity"], now - last > 0.5 {
            gravity = nil
            environment.inclineDegrees = nil
            floorWindow = StableGravityWindow()
            floorCalibrationProgress = 0
            isCalibratingFloor = false
        }
        if !isSimulating, connected,
           phase == .training || phase == .calibrating || (phase == .resting && !restInterrupted) {
            let last = measurementMode == .distance ? validDistanceAt : validAccelerationAt
            if ConnectionStage.measurement(last, now) != .receiving { pauseForConnectionLoss() }
        }
    }

    private func clearTelemetry() {
        resetHandshake()
        acceleration = nil
        accelerationHistory.removeAll()
        environment = SensorEnvironment(measuredAt: Date())
        gravity = nil
        floorReference = nil
        floorWindow = StableGravityWindow()
        floorCalibrationProgress = 0
        isCalibratingFloor = false
        receivedAt.removeAll()
        lastLiveSample = nil
        validDistanceAt = nil
        validAccelerationAt = nil
        distanceDate = nil
        accelerationDate = nil
        lastSensorDataAt = nil
        verifiedHardwareID = nil
        proximityPressed = false
        ledOn = false
        ledCharacteristic = nil
        lastGesture = "입력 대기"
        lastGestureSequence = nil
        deviceError = nil
    }

    func gesture(_ direction: UInt8) {
        expireTelemetry()
        guard recoveryCandidate == nil, pendingCompletion == nil else { return }
        switch (direction, phase) {
        case (4, .ready), (4, .finished):
            guard canMeasure, isSimulating || recordingAvailable else { return }
            isCalibratingFloor = false
            sessionEnvironment = environment
            sessionEnvironment?.measuredAt = Date()
            sessionEnvironment?.equipment = equipment
            sessionEnvironment?.place = place
            sessionEnvironment?.footwear = footwear
            reps = 0
            set = 1
            totalReps = 0
            completedSets = 0
            restInterrupted = false
            summary = nil
            sessionStart = Date()
            elapsedAccumulated = 0
            clockBegan = nil
            sessionID = isSimulating ? nil : UUID()
            restSeconds = workout.rest
            calibrate()
        case (4, .paused):
            guard canMeasure else { return }
            calibrate()
        case (3, .training), (3, .calibrating):
            guard descent == nil else { return }
            pause()
        case (1, .resting):
            guard canMeasure else { return }
            restInterrupted = false
            restTimer?.invalidate()
            set += 1
            reps = 0
            calibrate()
        case (2, .paused):
            finish()
        default:
            break
        }
    }

    func pause() {
        guard phase == .training || phase == .calibrating else { return }
        stopClock()
        resetMotion()
        phase = .paused
        checkpoint()
    }

    private func pauseForConnectionLoss() {
        if phase == .resting {
            if !restInterrupted { restSeconds = max(0, Int(ceil(restDeadline.timeIntervalSinceNow))) }
            restTimer?.invalidate()
            restInterrupted = true
            stopClock()
            checkpoint()
        } else {
            pause()
        }
    }

    private func calibrate() {
        resetMotion()
        phase = !isSimulating && measurementMode == .acceleration ? .training : .calibrating
        startClock()
        checkpoint()
    }

    private func resetMotion() {
        samples.removeAll()
        calibration.removeAll()
        calibrationStart = nil
        calibrationProgress = 0
        isSimulatingRep = false
        descent = nil
        reachedDepth = false
        shallow = false
        accelerationCounter = AccelerationCounter()
    }

    private func measure(_ millimeters: Double) {
        guard millimeters > 0 else {
            latestDistance = nil
            if measurementMode == .distance || isSimulating { resetMotion() }
            return
        }
        latestDistance = millimeters
        guard isSimulating || measurementMode == .distance else { return }
        guard phase == .calibrating || phase == .training else { return }

        samples.append(millimeters)
        if samples.count > 3 { samples.removeFirst() }
        guard samples.count == 3 else { return }
        let filtered = samples.sorted()[1]
        let now = ProcessInfo.processInfo.systemUptime

        if phase == .calibrating {
            if calibrationStart == nil { calibrationStart = now }
            calibration.append(filtered)
            if let start = calibrationStart {
                calibrationProgress = min(1, (now - start) / 2)
                if calibrationProgress == 1 {
                    baseline = calibration.reduce(0, +) / Double(calibration.count)
                    phase = .training
                    checkpoint()
                }
            }
            return
        }

        let depth = (baseline - filtered) / baseline
        if depth > (workout.exercise.returnDepth + 0.03), descent == nil {
            descent = now
            shallow = false
        }
        if depth >= workout.exercise.depth(for: workout.level) { reachedDepth = true }
        guard depth <= workout.exercise.returnDepth, let start = descent else { return }
        descent = nil
        defer { reachedDepth = false }
        guard now - start >= 0.5 else { return }
        shallow = !reachedDepth
        guard reachedDepth else { return }
        countRep()
    }

    private func countRep() {
        reps += 1
        totalReps += 1
        guard reps == workout.target else { checkpoint(); return }
        completedSets += 1
        if set == workout.sets {
            finish()
        } else {
            phase = .resting
            restInterrupted = false
            restSeconds = workout.rest
            restDeadline = Date().addingTimeInterval(Double(workout.rest))
            scheduleRestTimer()
            checkpoint()
        }
    }
}
