import SwiftUI

@main
struct MYMSApp: App {
    @StateObject private var accounts = Accounts()

    init() {
        if ProcessInfo.processInfo.environment["MYMS_POSE_DIAGNOSTICS"] != "1" {
            let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MYMS-pose-diagnostic.json")
            try? FileManager.default.removeItem(at: url)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let account = accounts.current {
                WorkoutHome(account: account, accounts: accounts).id(account.id)
            } else if accounts.restoring {
                ProgressView("로그인 상태 확인 중")
            } else {
                LoginScreen(accounts: accounts)
            }
        }
    }
}
