import SwiftUI

struct WorkoutHome: View {
    @Environment(\.dynamicTypeSize) var typeSize
    @ScaledMetric(relativeTo: .largeTitle) var repFontSize = 68.0
    @StateObject var coach = Coach()
    @StateObject var store: WorkoutStore
    let account: LocalAccount
    @ObservedObject var accounts: Accounts
    @State var confirmDeletion = false
    @State var deletionPassword = ""

    init(account: LocalAccount, accounts: Accounts) {
        self.account = account
        self.accounts = accounts
        _store = StateObject(wrappedValue: WorkoutStore(token: accounts.token))
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
            }
            .tint(Color(red: 0.16, green: 0.62, blue: 0.42))
            .onReceive(coach.$result.compactMap { $0 }) { store.save($0) }
            .task { await store.load() }
            .safeAreaInset(edge: .top) {
                if let error = store.syncError {
                    HStack {
                        Text(error).font(.footnote)
                        Spacer()
                        Button("다시 시도") { store.retry() }
                    }
                    .padding()
                    .background(.regularMaterial)
                } else if !store.loaded {
                    ProgressView("운동 데이터 불러오는 중").padding()
                }
            }
    }
}
