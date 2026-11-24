import SwiftUI
import AVFoundation
import CoreImage

extension WorkoutHome {
    var session: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 780 && !typeSize.isAccessibilitySize
                let inset: CGFloat = wide ? 28 : 16
                let width = min(1400, max(0, geometry.size.width - inset * 2))
                let controlsWidth: CGFloat = wide ? min(340, width * 0.3) : width

                ScrollView {
                    if wide {
                        HStack(alignment: .top, spacing: 24) {
                            cameraPanel
                                .frame(width: max(0, width - controlsWidth - 24))
                            workoutDetails
                                .frame(width: controlsWidth)
                        }
                        .padding(inset)
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 20) {
                            cameraPanel
                            workoutDetails
                        }
                        .frame(width: width)
                        .padding(inset)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("운동")
        }
    }

    private var cameraPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $showsWorkoutCamera) {
                Label("카메라 자세 보조", systemImage: "figure.stand")
                    .font(.title2.bold())
            }
            if showsWorkoutCamera && tab == 1 {
                WorkoutCameraView()
            } else {
                ContentUnavailableView("내 자세를 크게 확인하세요", systemImage: "camera",
                    description: Text("카메라 자세 보조를 켜면 영상과 관절 표시를 확인할 수 있습니다."))
                    .frame(maxWidth: .infinity, minHeight: 280)
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var workoutDetails: some View {
        VStack(spacing: 16) {
            progressPanel
            sessionControls
            measurementSummary
            sessionResult
        }
    }

    private var measurementSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(coach.isSimulating ? "센서 없이 시연 중" : coach.measurementMode.rawValue,
                  systemImage: "waveform.path.ecg")
                .font(.headline)
            if coach.isSimulating {
                Text("시연 기록과 포인트는 저장되지 않습니다.")
            } else {
                Text(coach.connection)
                if coach.measurementMode == .acceleration {
                    Text(coach.acceleration.map { "\($0.formatted(.number.precision(.fractionLength(2)))) g" } ?? "IMU 데이터 대기 중")
                } else {
                    Text(coach.latestDistance.map { "\(($0 / 10).formatted(.number.precision(.fractionLength(1)))) cm" } ?? "유효 거리값 대기 중")
                }
                if coach.canSelect && coach.measurementMode == .distance {
                    Text(coach.workout.exercise.placement)
                }
                if coach.phase == .calibrating {
                    ProgressView(value: coach.calibrationProgress)
                        .accessibilityLabel("시작 거리 측정 진행률")
                }
            }
            Button { tab = 4 } label: {
                Label("센서 연결 및 설정", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.bordered)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var progressPanel: some View {
        VStack(spacing: 8) {
            Text(coach.workout.exercise.rawValue).font(.title2.bold())
            Text("\(coach.workout.level.title) · 세트 \(coach.set) / \(coach.workout.sets)")
            Text("\(coach.reps) / \(coach.workout.target)")
                .font(.system(size: repFontSize, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1).monospacedDigit()
                .accessibilityLabel("\(coach.workout.target)회 중 \(coach.reps)회")
            ProgressView(value: Double(coach.reps), total: Double(coach.workout.target)).tint(.mint)
            Text(coach.phase.rawValue).font(.headline)
            if coach.phase == .resting {
                Text("남은 휴식 \(coach.restSeconds)초").monospacedDigit()
                if coach.restInterrupted {
                    Text("휴식을 멈췄습니다. 센서를 연결한 뒤 남은 휴식 재개 또는 다음 세트를 눌러주세요.")
                        .font(.footnote)
                }
            }
            if coach.phase == .paused {
                Text("센서를 연결한 뒤 재개를 눌러주세요. 앱이 꺼져 있거나 센서 연결이 끊긴 동안의 동작은 집계되지 않습니다.")
                    .font(.footnote)
            }
            if coach.shallow {
                Text("동작 범위를 조금 더 늘려 보세요").foregroundStyle(.yellow)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .foregroundStyle(.white)
        .background(Color(red: 0.05, green: 0.29, blue: 0.22), in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private var sessionResult: some View {
        if coach.phase == .finished, let summary = coach.summary {
            VStack(alignment: .leading, spacing: 8) {
                Text(coach.isSimulating ? "시연 결과" : "운동 결과").font(.headline)
                LabeledContent("유효 횟수", value: "\(summary.reps)회")
                LabeledContent("완료 세트", value: "\(summary.sets) / \(summary.workout.sets)")
                LabeledContent("경과 시간", value: "\(summary.seconds)초")
                if let saved = store.records.first(where: { $0.id == summary.id }) {
                    LabeledContent("획득 포인트", value: "\(saved.points) P")
                }
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var sessionControls: some View {
        VStack(spacing: 12) {
            if coach.isSimulating && coach.phase == .training {
                Button("가상 동작 1회") { coach.simulateRep() }
                    .disabled(coach.isSimulatingRep)
            }
            switch coach.phase {
            case .ready, .finished:
                Button("운동 시작") { coach.gesture(4) }.disabled(!coach.canMeasure || !store.loaded || !coach.canSelect)
            case .calibrating, .training:
                Button("일시정지") { coach.pause() }
            case .paused:
                Button("재개") { coach.gesture(4) }.disabled(!coach.canMeasure || !store.loaded)
                Button("운동 종료") { coach.finish() }
            case .resting:
                if coach.restInterrupted {
                    Button("남은 휴식 재개") { coach.resumeRest() }
                        .disabled(!coach.canMeasure || !store.loaded)
                }
                Button("다음 세트") { coach.gesture(1) }.disabled(!coach.canMeasure || !store.loaded)
                Button("운동 종료") { coach.finish() }
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(coach.persistenceError != nil)
    }
}

private struct WorkoutCameraView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorized = false
    @State private var checked = false
    @State private var failed = false

    @State private var position = AVCaptureDevice.Position.front
    @State private var status = "자세 확인 중"

    var body: some View {
        VStack(spacing: 16) {
            Picker("카메라", selection: $position) {
                Text("전면").tag(AVCaptureDevice.Position.front)
                Text("후면").tag(AVCaptureDevice.Position.back)
            }
            .pickerStyle(.segmented)
            .onChange(of: position) {
                failed = false
                status = "자세 확인 중"
            }
            if authorized, scenePhase == .active, !failed {
                WorkoutCameraPreview(position: position, onStatus: { status = $0 }) { failed = true }
                    .id(position)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .topLeading) {
                        Text(status)
                            .font(.callout.bold())
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                    .accessibilityLabel("카메라 미리보기")
            } else if failed {
                ContentUnavailableView("카메라를 열 수 없어요", systemImage: "camera")
            } else if checked && !authorized {
                ContentUnavailableView("카메라 권한이 필요해요", systemImage: "camera",
                    description: Text("설정에서 MYMS의 카메라 접근을 허용해 주세요."))
            } else if !checked {
                ProgressView("카메라 준비 중")
            }
            if authorized, !failed { Text(status).font(.headline) }
            Text("iPad를 옆에 세우고 운동할 때 몸 전체가 화면에 들어오도록 위치를 맞추세요.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            let allowed: Bool
            if status == .notDetermined {
                allowed = await AVCaptureDevice.requestAccess(for: .video)
            } else {
                allowed = status == .authorized
            }
            guard !Task.isCancelled else { return }
            authorized = allowed
            checked = true
        }
    }
}

private struct WorkoutCameraPreview: UIViewRepresentable {
    let position: AVCaptureDevice.Position
    let onStatus: (String) -> Void
    let onFailure: () -> Void

    final class Preview: UIImageView {
        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
        var rotation: AVCaptureDevice.RotationCoordinator?
        var observation: NSKeyValueObservation?
        var active = true
    }

    final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        let session = AVCaptureSession()
        let output = AVCaptureVideoDataOutput()
        let queue = DispatchQueue(label: "MYMS.camera")
        let context = CIContext()
        var estimator: MoveNetPoseEstimator?
        var setupError: String?
        var handEstimator: HandGestureEstimator?
        var handSetupError: String?
        var lastFrame = -Double.infinity
        var lastDiagnostic = -Double.infinity
        var onFrame: ((UIImage, String) -> Void)?

        func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard time - lastFrame >= 0.12, let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
            lastFrame = time
            let frame = CIImage(cvPixelBuffer: buffer)
            guard let image = context.createCGImage(frame, from: frame.extent) else { return }

            let started = CFAbsoluteTimeGetCurrent()
            var landmarks: [PoseLandmark] = []
            var analysisError: String?
            if estimator == nil && setupError == nil {
                do { estimator = try MoveNetPoseEstimator() }
                catch { setupError = error.localizedDescription }
            }
            do {
                if let estimator { landmarks = try estimator.predict(image) }
                else { analysisError = setupError }
            } catch { analysisError = error.localizedDescription }
            var hands: [TrackedHand] = []
            var handError: String?
            if handEstimator == nil && handSetupError == nil {
                do { handEstimator = try HandGestureEstimator() }
                catch { handSetupError = error.localizedDescription }
            }
            do {
                if let handEstimator, time.isFinite, time >= 0, time < Double(Int.max / 1000) {
                    hands = try handEstimator.predict(image, timestampMilliseconds: Int(time * 1000))
                } else { handError = handSetupError ?? "카메라 시간 정보를 확인할 수 없습니다." }
            } catch { handError = error.localizedDescription }
            let milliseconds = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            let points = Dictionary(uniqueKeysWithValues: landmarks.map { ($0.joint, $0) })
            let size = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let annotated = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
                let ctx = renderer.cgContext
                ctx.setStrokeColor(UIColor.systemGreen.cgColor)
                ctx.setFillColor(UIColor.systemGreen.cgColor)
                ctx.setShadow(offset: .zero, blur: 5, color: UIColor.black.cgColor)
                ctx.setLineWidth(6)
                func location(_ joint: PoseJoint) -> CGPoint? {
                    guard let point = points[joint] else { return nil }
                    return CGPoint(x: point.x * size.width, y: point.y * size.height)
                }
                for (a, b) in PoseJoint.connections {
                    guard let start = location(a), let end = location(b) else { continue }
                    ctx.move(to: start)
                    ctx.addLine(to: end)
                    ctx.strokePath()
                }
                let labeledJoints: Set<PoseJoint> = [.nose, .leftElbow, .rightElbow, .leftWrist, .rightWrist, .leftKnee, .rightKnee]
                func drawDot(_ p: CGPoint, name: String?) {
                    let dot = CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)
                    ctx.setFillColor(UIColor.systemYellow.cgColor)
                    ctx.fillEllipse(in: dot)
                    ctx.setStrokeColor(UIColor.black.cgColor)
                    ctx.setLineWidth(2)
                    ctx.strokeEllipse(in: dot)
                    if let name {
                        (name as NSString).draw(at: CGPoint(x: min(p.x + 10, size.width - 80), y: max(0, p.y - 22)),
                            withAttributes: [.font: UIFont.boldSystemFont(ofSize: 17),
                                .foregroundColor: UIColor.white, .strokeColor: UIColor.black, .strokeWidth: -3])
                    }
                }
                for joint in PoseJoint.allCases {
                    guard let p = location(joint) else { continue }
                    drawDot(p, name: labeledJoints.contains(joint) ? joint.title : nil)
                }

                HandOverlay.draw(hands, in: ctx, size: size)
            }
            let status: String
            let visibleCount = landmarks.count
            if let analysisError {
                status = "MoveNet Thunder 오류 · \(analysisError)"
            } else if visibleCount > 0 {
                status = "Thunder · 관절 \(visibleCount)/17개 · \(milliseconds)ms"
            } else {
                status = "Thunder · 전신 감지 대기 · 머리부터 발끝까지 보여 주세요"
            }
            let handStatus: String
            if let handError { handStatus = "손 추적 오류 · \(handError)" }
            else if hands.isEmpty { handStatus = "손 감지 대기 · 손가락이 보이게 해 주세요" }
            else { handStatus = "손 \(hands.count)개 · " + hands.map { $0.gesture.rawValue }.joined(separator: " / ") }
            let combinedStatus = status + "\n" + handStatus
            if ProcessInfo.processInfo.environment["MYMS_POSE_DIAGNOSTICS"] == "1", time - lastDiagnostic >= 1 {
                lastDiagnostic = time
                let diagnostic: [String: Any] = [
                    "date": ISO8601DateFormatter().string(from: Date()),
                    "engine": "MoveNet Thunder float16 v4",
                    "frameWidth": image.width, "frameHeight": image.height,
                    "rotation": connection.videoRotationAngle,
                    "mirrored": connection.isVideoMirrored,
                    "drawnJoints": visibleCount,
                    "hands": hands.map { ["points": $0.visiblePoints.count, "gesture": $0.gesture.rawValue, "score": $0.score] as [String: Any] },
                    "handError": handError ?? "",
                    "joints": landmarks.map { ["name": $0.joint.title, "score": $0.score] as [String: Any] },
                    "inferenceMilliseconds": milliseconds,
                    "error": analysisError ?? "", "status": combinedStatus
                ]
                if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys]) {
                    let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("MYMS-pose-diagnostic.json")
                    try? data.write(to: url, options: [.atomic, .completeFileProtection])
                }
            }
            onFrame?(annotated, combinedStatus)
        }
    }

    func makeCoordinator() -> Coordinator {
        if ProcessInfo.processInfo.environment["MYMS_POSE_DIAGNOSTICS"] != "1" {
            let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MYMS-pose-diagnostic.json")
            try? FileManager.default.removeItem(at: url)
        }
        return Coordinator()
    }

    func makeUIView(context: Context) -> Preview {
        let view = Preview()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        let camera = context.coordinator
        let reportFailure = { [weak view] in
            DispatchQueue.main.async {
                guard view?.active == true else { return }
                onFailure()
            }
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            reportFailure()
            return view
        }
        let rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        view.rotation = rotation
        view.observation = rotation.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            camera.queue.async {
                if let connection = camera.output.connection(with: .video),
                   connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
        }
        let initialAngle = rotation.videoRotationAngleForHorizonLevelCapture
        camera.queue.async {
            guard let input = try? AVCaptureDeviceInput(device: device),
                  camera.session.canAddInput(input) else {
                reportFailure()
                return
            }
            camera.session.addInput(input)
            if camera.session.canSetSessionPreset(.hd1280x720) { camera.session.sessionPreset = .hd1280x720 }
            guard camera.session.canAddOutput(camera.output) else {
                reportFailure()
                return
            }
            camera.output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            camera.output.alwaysDiscardsLateVideoFrames = true
            camera.output.setSampleBufferDelegate(camera, queue: camera.queue)
            camera.session.addOutput(camera.output)
            if let connection = camera.output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(initialAngle) {
                    connection.videoRotationAngle = initialAngle
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = position == .front
                }
            }
            camera.onFrame = { [weak view] image, status in
                DispatchQueue.main.async {
                    guard let view, view.active else { return }
                    view.image = image
                    onStatus(status)
                }
            }
            camera.session.startRunning()
            if !camera.session.isRunning { reportFailure() }
        }
        return view
    }

    func updateUIView(_ uiView: Preview, context: Context) {}

    static func dismantleUIView(_ uiView: Preview, coordinator: Coordinator) {
        uiView.active = false
        uiView.observation?.invalidate()
        coordinator.queue.async {
            coordinator.output.setSampleBufferDelegate(nil, queue: nil)
            coordinator.session.stopRunning()
        }
    }
}
