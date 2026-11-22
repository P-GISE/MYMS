import SwiftUI

@main
struct MYMSApp: App {
    @StateObject private var accounts = Accounts()

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
