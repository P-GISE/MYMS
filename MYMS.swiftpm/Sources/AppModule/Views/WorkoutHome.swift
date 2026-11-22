import SwiftUI

struct WorkoutHome: View {
    @Environment(\.dynamicTypeSize) var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) var repFontSize = 68.0
    @StateObject var coach = Coach()
    @StateObject var store: WorkoutStore
    let account: LocalAccount
    @ObservedObject var accounts: Accounts
    @State var confirmDeletion = false
    @State var deletionPassword = ""
    @State private var confirmProgressDiscard = false

    init(account: LocalAccount, accounts: Accounts) {
        self.account = account
        self.accounts = accounts
        _store = StateObject(wrappedValue: WorkoutStore(accountID: account.id, accounts: accounts))
    }
    @State var tab = 0
    @State var editing: Workout?
    @State var guide: Workout?
    @State var deleting: Workout?
    @State var deletingRecord: WorkoutRecord?

    var body: some View {
            TabView(selection: $tab) {
                plans.tabItem { Label("운동 계획", systemImage: "list.bullet") }.tag(0)
                session.tabItem { Label("운동", systemImage: "figure.strengthtraining.traditional") }.tag(1)
                history.tabItem { Label("기록", systemImage: "clock") }.tag(2)
                settings.tabItem { Label("설정", systemImage: "gearshape") }.tag(3)
                SensorDashboard(coach: coach).tabItem { Label("센서", systemImage: "waveform.path.ecg") }.tag(4)
            }
            .tint(Color(red: 0.16, green: 0.62, blue: 0.42))
            .task {
                coach.onCheckpoint = { [store] progress in
                    MainActor.assumeIsolated { store.updateProgress(progress) }
                }
                coach.onComplete = { [store] record in
                    MainActor.assumeIsolated { store.complete(record) }
                }
                coach.onDiscard = { [store] in
                    MainActor.assumeIsolated { store.discardProgress() }
                }
                if coach.canSelect, let progress = store.progress { coach.offerRecovery(progress) }
                await store.load()
            }
            .onDisappear {
                coach.suspendForBackground()
                coach.stopConnection()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { coach.suspendForBackground() }
            }
            .onChange(of: store.loaded, initial: true) { _, loaded in
                coach.recordingAvailable = loaded
                if loaded, coach.canSelect, let progress = store.progress { coach.offerRecovery(progress) }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    if let error = coach.persistenceError ?? store.localError ?? store.syncError {
                        HStack {
                            Text(error).font(.footnote)
                            Spacer()
                            Button("다시 시도") {
                                if coach.retryPersistence() { store.retry() }
                            }
                        }
                        .padding()
                        .background(.regularMaterial)
                    } else if !store.loaded {
                        ProgressView("운동 데이터 불러오는 중").padding()
                    }
                    if let progress = coach.recoveryCandidate {
                        recoveryCard(progress)
                    }
                }
            }
            .confirmationDialog("진행 중인 운동 기록을 버릴까요?", isPresented: $confirmProgressDiscard, titleVisibility: .visible) {
                Button("진행 기록 버리기", role: .destructive) { _ = coach.discardRecovery() }
                Button("취소", role: .cancel) { }
            } message: {
                Text("저장된 진행 횟수와 세트가 삭제됩니다. 완료 기록과 포인트는 추가되지 않습니다.")
            }
    }

    private func recoveryCard(_ progress: WorkoutProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("진행 중이던 운동이 있습니다", systemImage: "arrow.counterclockwise")
                .font(.headline)
            Text("\(progress.workout.exercise.rawValue) · \(progress.measurementSource)")
            Text("세트 \(progress.set) / \(progress.workout.sets) · 현재 \(progress.reps) / \(progress.workout.target)회 · 누적 \(progress.totalReps)회")
                .font(.subheadline).monospacedDigit()
            Text("복구 후 센서를 연결하고 운동을 재개하세요. 휴식 중이었다면 남은 휴식 재개 또는 다음 세트를 눌러주세요. 앱이 꺼져 있거나 센서 연결이 끊긴 동안의 동작은 집계되지 않습니다.")
                .font(.footnote).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack { recoveryButtons }
                VStack(alignment: .leading) { recoveryButtons }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var recoveryButtons: some View {
        Button("복구") {
            if coach.restoreRecovery() { tab = 1 }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!store.loaded || coach.persistenceError != nil)
        Button("진행 기록 버리기", role: .destructive) { confirmProgressDiscard = true }
            .buttonStyle(.bordered)
    }
}
