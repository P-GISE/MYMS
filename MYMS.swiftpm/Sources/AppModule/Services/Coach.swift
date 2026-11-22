import Foundation
import Combine
import CoreBluetooth

final class Coach: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum Phase: String {
        case ready = "대기", calibrating = "시작 자세를 유지하세요", training = "운동 중"
        case paused = "일시정지", resting = "휴식", finished = "운동 종료"
    }

    @Published private(set) var phase = Phase.ready
    @Published private(set) var connection = "Bluetooth 준비 중"
    @Published private(set) var connected = false
    @Published private(set) var reps = 0
    @Published private(set) var set = 1
    @Published private(set) var restSeconds = 30
    @Published private(set) var shallow = false
    @Published private(set) var workout = Workout()
    @Published private(set) var result: WorkoutRecord?
    @Published private(set) var summary: WorkoutRecord?
    @Published private(set) var latestDistance: Double?
    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var isSimulating = false
    @Published private(set) var isSimulatingRep = false
    private var simulationTimer: Timer?
    private var simulationSample = 0
    private var lastLiveSample: TimeInterval?
    private var distanceTimer: Timer?

    var canMeasure: Bool { latestDistance != nil && (isSimulating || connected) }

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

    var canSelect: Bool { phase == .ready || phase == .finished }

    func select(_ plan: Workout) {
        guard canSelect else { return }
        workout = plan
        reps = 0
        set = 1
        phase = .ready
    }

    func finish() {
        restTimer?.invalidate()
        resetMotion()
        phase = .finished
        guard totalReps > 0 else { return }
        let completed = WorkoutRecord(workout: workout, reps: totalReps, sets: completedSets,
                               seconds: max(0, Int(Date().timeIntervalSince(sessionStart))),
                               points: totalReps * workout.level.rawValue + completedSets * 5)
        summary = completed
        if !isSimulating { result = completed }
    }

    private let suffix = "-E8F2-537E-4F6C-D104768A1214"
    private lazy var service = CBUUID(string: "19B10000" + suffix)
    private lazy var distance = CBUUID(string: "19B10004" + suffix)
    private lazy var gestureID = CBUUID(string: "19B10005" + suffix)
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
            guard let self, !self.isSimulating, let last = self.lastLiveSample,
                  ProcessInfo.processInfo.systemUptime - last > 1 else { return }
            self.lastLiveSample = nil
            self.measure(0)
        }
    }

    deinit {
        simulationTimer?.invalidate()
        distanceTimer?.invalidate()
        restTimer?.invalidate()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            connected = false
            if !isSimulating { measure(0) }
            connection = "Bluetooth 상태를 확인하세요"
            return
        }
        scan()
    }

    func stopConnection() {
        simulationTimer?.invalidate()
        distanceTimer?.invalidate()
        central.stopScan()
        if let sensor { central.cancelPeripheralConnection(sensor) }
        sensor?.delegate = nil
        central.delegate = nil
    }

    private func scan() {
        guard central.state == .poweredOn else { return }
        connection = "MYMS 센서 검색 중"
        central.scanForPeripherals(withServices: [service])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        sensor = peripheral
        peripheral.delegate = self
        connection = "연결 중"
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        scan()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connected = false
        if !isSimulating { measure(0) }
        scan()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let fitness = peripheral.services?.first(where: { $0.uuid == service }) else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([distance, gestureID], for: fitness)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let characteristics = service.characteristics ?? []
        guard characteristics.contains(where: { $0.uuid == distance }) else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        for characteristic in characteristics where characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == distance else { return }
        connected = characteristic.isNotifying && error == nil
        connection = connected ? "센서 연결됨" : "거리 수신 실패"
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !isSimulating, error == nil, let data = characteristic.value, data.count == 2 else { return }
        let bytes = Array(data)
        if characteristic.uuid == distance {
            lastLiveSample = ProcessInfo.processInfo.systemUptime
            measure(Double(Int(bytes[0]) + Int(bytes[1]) * 256))
        } else if characteristic.uuid == gestureID {
            gesture(bytes[0])
        }
    }

    func gesture(_ direction: UInt8) {
        switch (direction, phase) {
        case (4, .ready), (4, .finished):
            guard canMeasure else { return }
            reps = 0
            set = 1
            totalReps = 0
            completedSets = 0
            summary = nil
            sessionStart = Date()
            calibrate()
        case (4, .paused):
            guard canMeasure else { return }
            calibrate()
        case (3, .training), (3, .calibrating):
            guard descent == nil else { return }
            pause()
        case (1, .resting):
            guard canMeasure else { return }
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
        resetMotion()
        phase = .paused
    }

    private func calibrate() {
        resetMotion()
        phase = .calibrating
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
    }

    private func measure(_ millimeters: Double) {
        guard millimeters > 0 else {
            latestDistance = nil
            resetMotion()
            return
        }
        latestDistance = millimeters
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
        reps += 1
        totalReps += 1
        guard reps == workout.target else { return }
        completedSets += 1
        if set == workout.sets {
            finish()
        } else {
            phase = .resting
            restSeconds = workout.rest
            restDeadline = Date().addingTimeInterval(Double(workout.rest))
            restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.restSeconds = max(0, Int(ceil(self.restDeadline.timeIntervalSinceNow)))
                if self.restSeconds == 0 { self.gesture(1) }
            }
        }
    }
}
