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
    @State var tab: WorkoutDestination = .plans
    @State var historyStatisticsSource: WorkoutStatistics.Source = .exercise
    @State var showsWorkoutCamera = false
    @State var workoutDetailsHeight: CGFloat = 320
    @State var editing: Workout?
    @State var guide: Workout?
    @State var deleting: Workout?
    @State var deletingRecord: WorkoutRecord?

    var body: some View {
        navigation
            .tint(MYMSStyle.accent)
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
            .onChange(of: store.plans, initial: true) { _, plans in
                coach.reconcilePlans(plans)
            }
            .onChange(of: coach.phase) { _, _ in
                coach.reconcilePlans(store.plans)
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    if let error = coach.persistenceError ?? store.localError ?? store.syncError {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange).accessibilityHidden(true)
                            Text(error).font(.footnote)
                            Spacer()
                            Button("다시 시도") {
                                if coach.retryPersistence() { store.retry() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
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

    @ViewBuilder
    private var navigation: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $tab) {
                ForEach(WorkoutDestination.allCases) { destination in
                    Tab(destination.title, systemImage: destination.symbol, value: destination) {
                        page(for: destination)
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .tabViewSidebarHeader {
                MYMSWordmark()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(MYMSStyle.ink, in: RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            TabView(selection: $tab) {
                ForEach(WorkoutDestination.allCases) { destination in
                    page(for: destination)
                        .tabItem { Label(destination.title, systemImage: destination.symbol) }
                        .tag(destination)
                }
            }
        }
    }

    @ViewBuilder
    private func page(for destination: WorkoutDestination) -> some View {
        switch destination {
        case .plans: plans
        case .workout: session
        case .history: history
        case .sensors: SensorDashboard(coach: coach) { tab = .workout }
        case .settings: settings
        }
    }

    private func recoveryCard(_ progress: WorkoutProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("진행 중이던 운동이 있습니다", systemImage: "arrow.counterclockwise")
                .font(.headline)
            Text("\(progress.workout.exercise.rawValue) · \(progress.measurementSource)")
            Text("세트 \(progress.set) / \(progress.workout.sets) · 현재 \(progress.reps) / \(progress.workout.target)회 · 누적 \(progress.totalReps)회")
                .font(.subheadline).monospacedDigit()
            Text("이어서 하려면 복구 후 센서를 연결하세요. 중단 중의 동작은 집계되지 않습니다.")
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
        Button("운동 복구") {
            if coach.restoreRecovery() { tab = .workout }
        }
        .mymsPrimaryButton()
        .disabled(!store.loaded || coach.persistenceError != nil)
        Button("진행 기록 버리기", role: .destructive) { confirmProgressDiscard = true }
            .buttonStyle(.bordered)
    }
}

enum WorkoutDestination: CaseIterable, Identifiable {
    case plans, workout, history, sensors, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .plans: "운동 계획"
        case .workout: "운동"
        case .history: "기록"
        case .sensors: "센서"
        case .settings: "설정"
        }
    }

    var symbol: String {
        switch self {
        case .plans: "list.clipboard"
        case .workout: "figure.strengthtraining.traditional"
        case .history: "clock.arrow.circlepath"
        case .sensors: "sensor.tag.radiowaves.forward"
        case .settings: "gearshape"
        }
    }
}
