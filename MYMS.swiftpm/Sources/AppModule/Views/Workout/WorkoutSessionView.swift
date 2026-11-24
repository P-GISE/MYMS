import SwiftUI
import AVFoundation
import Vision
import CoreImage

extension WorkoutHome {
    var session: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 780 && !typeSize.isAccessibilitySize
                let inset: CGFloat = wide ? 28 : 16
                let width = min(wide ? 1120 : 620, max(0, geometry.size.width - inset * 2))
                let panelWidth = wide ? (width - 20) / 2 : width
                let layout = wide
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                    : AnyLayout(VStackLayout(spacing: 16))

                ScrollView {
                    layout {
                        sensorPanel.frame(width: panelWidth)
                        VStack(spacing: 16) {
                            progressPanel
                            sessionControls
                            sessionResult
                        }
                        .frame(width: panelWidth)
                    }
                    .padding(inset)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("운동")
        }
    }

    private var sensorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $showsWorkoutCamera) {
                Label("카메라 자세 보조", systemImage: "camera")
            }
            if showsWorkoutCamera && tab == 1 {
                WorkoutCameraView()
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }

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

            SensorConnectionCard(coach: coach)

            VStack(alignment: .leading, spacing: 8) {
                Text("현재 측정값").font(.headline)
                if !coach.isSimulating, coach.measurementMode == .acceleration {
                    Text(coach.acceleration.map { "\($0.formatted(.number.precision(.fractionLength(2)))) g" } ?? "IMU 데이터 대기 중")
                        .font(.title2.monospacedDigit())
                } else if let millimeters = coach.latestDistance {
                    Text("\((millimeters / 10).formatted(.number.precision(.fractionLength(1)))) cm")
                        .font(.title2.monospacedDigit())
                } else {
                    Text(coach.connected ? "유효 거리값 대기 중" : "센서 데이터 대기 중")
                        .foregroundStyle(.secondary)
                }
                if coach.isSimulating {
                    Text("시연 기록과 포인트는 저장되지 않습니다.")
                        .foregroundStyle(.secondary)
                } else if coach.canSelect && coach.measurementMode == .distance {
                    Text(coach.workout.exercise.placement).foregroundStyle(.secondary)
                } else if coach.phase == .training && coach.measurementMode == .distance && coach.latestDistance == nil {
                    Text("측정 일시 중지").foregroundStyle(.orange)
                }
                if coach.phase == .calibrating {
                    ProgressView(value: coach.calibrationProgress)
                        .accessibilityLabel("시작 거리 측정 진행률")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 8) {
                Text("운동 환경").font(.headline)
                LabeledContent("운동기구", value: coach.equipment.rawValue)
                LabeledContent("장소", value: coach.place.rawValue)
                LabeledContent("신발", value: coach.footwear.rawValue)
                Text("센서 탭에서 밝기·바닥 경사를 측정하고 환경을 선택하세요. 보드를 바닥에 둔 상태로 운동 시작을 누르면 환경이 저장됩니다. IMU 동작 테스트는 그다음 보드를 들어 진행하세요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
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
        let request = VNDetectHumanBodyPoseRequest()
        var lastFrame = -Double.infinity
        var onFrame: ((UIImage, String) -> Void)?

        func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard time - lastFrame >= 0.12, let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
            lastFrame = time
            let frame = CIImage(cvPixelBuffer: buffer)
            guard let image = context.createCGImage(frame, from: frame.extent) else { return }

            let detected = (try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])) != nil
            typealias Joint = VNHumanBodyPoseObservation.JointName
            var points: [Joint: VNRecognizedPoint] = [:]
            if detected, let poses = request.results, poses.count == 1, let pose = poses.first,
               let recognized = try? pose.recognizedPoints(.all) {
                points = recognized.filter { $0.value.confidence >= 0.25 }
            }
            let left: [Joint] = [.leftWrist, .leftElbow, .leftShoulder, .leftHip, .leftKnee, .leftAnkle]
            let right: [Joint] = [.rightWrist, .rightElbow, .rightShoulder, .rightHip, .rightKnee, .rightAnkle]
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
                func location(_ joint: Joint) -> CGPoint? {
                    guard let point = points[joint] else { return nil }
                    return CGPoint(x: point.location.x * size.width, y: (1 - point.location.y) * size.height)
                }
                for chain in [left, right, [.leftShoulder, .rightShoulder], [.leftHip, .rightHip]] {
                    for (a, b) in zip(chain, chain.dropFirst()) {
                        guard let start = location(a), let end = location(b) else { continue }
                        ctx.move(to: start)
                        ctx.addLine(to: end)
                        ctx.strokePath()
                    }
                }
                for joint in left + right {
                    guard let p = location(joint) else { continue }
                    ctx.fillEllipse(in: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
                }
            }
            let status: String
            let visibleCount = (left + right).filter { points[$0] != nil }.count
            if !detected {
                status = "자세 분석에 실패했어요. 카메라를 다시 켜 주세요"
            } else if (request.results?.count ?? 0) > 1 {
                status = "한 사람만 화면에 들어오도록 해 주세요"
            } else if left.allSatisfy({ points[$0] != nil }) || right.allSatisfy({ points[$0] != nil }) {
                status = "자세 추적 중 · 관절 \(visibleCount)개"
            } else if visibleCount > 0 {
                status = "관절 \(visibleCount)개 감지 · 손목부터 발목까지 보여 주세요"
            } else {
                status = "관절 감지 대기 · 밝은 곳에서 몸 전체를 보여 주세요"
            }
            onFrame?(annotated, status)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

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
            if camera.session.canSetSessionPreset(.vga640x480) { camera.session.sessionPreset = .vga640x480 }
            guard camera.session.canAddOutput(camera.output) else {
                reportFailure()
                return
            }
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
