import SwiftUI

struct LoginScreen: View {
    @ObservedObject var accounts: Accounts
    @State private var email = ""
    @State private var password = ""
    @FocusState private var passwordFocused: Bool

    var body: some View {
        NavigationStack {
            AccountPage(title: "로그인", subtitle: "계정에 저장한 운동 계획과 기록을 이어서 확인하세요.") {
                AccountEmailField(email: $email)
                    .submitLabel(.next)
                    .onSubmit { passwordFocused = true }
                AccountField(title: "비밀번호") {
                    SecureField("비밀번호 입력", text: $password)
                        .accessibilityLabel("비밀번호")
                        .textContentType(.password)
                        .focused($passwordFocused)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                }
                if let message = accounts.message {
                    Label(message, systemImage: "info.circle")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: signIn) {
                    HStack {
                        if accounts.busy { ProgressView().controlSize(.small) }
                        Text(accounts.busy ? "로그인 중" : "로그인")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                }
                .mymsPrimaryButton()
                .controlSize(.large)
                .disabled(accounts.busy || email.isEmpty || password.isEmpty)

                NavigationLink("새 계정 만들기") { RegistrationScreen(accounts: accounts) }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(accounts.busy)
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        accounts.enterLocalMode()
                    } label: {
                        Label("로그인 없이 이 기기에서 시작", systemImage: "ipad")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .disabled(accounts.busy)
                    Text("운동 기록은 이 기기에만 저장됩니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { password = "" }
        }
    }

    private func signIn() {
        guard !accounts.busy, !email.isEmpty, !password.isEmpty else { return }
        accounts.signIn(email: email, password: password)
    }
}
