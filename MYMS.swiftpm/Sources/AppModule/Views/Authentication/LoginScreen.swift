import SwiftUI

struct LoginScreen: View {
    @ObservedObject var accounts: Accounts
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            AccountPage(title: "로그인", subtitle: "MYMS 운동 계획과 기록을 이어서 확인하세요.") {
                AccountEmailField(email: $email)
                    .submitLabel(.next)
                AccountField(title: "비밀번호") {
                    SecureField("비밀번호 입력", text: $password)
                        .accessibilityLabel("비밀번호")
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                }
                if let message = accounts.message {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
                Button(action: signIn) {
                    Text("로그인").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(accounts.busy || email.isEmpty || password.isEmpty)

                HStack(spacing: 6) {
                    Text("처음 이용하시나요?").foregroundStyle(.secondary)
                    NavigationLink("회원가입") { RegistrationScreen(accounts: accounts) }
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                Button("로그인 없이 이 기기에서 시작") { accounts.enterLocalMode() }
                    .disabled(accounts.busy)
                    .frame(maxWidth: .infinity)
                Text("로컬 기록은 이 기기에 저장되며 서버 계정과 별도로 관리됩니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func signIn() {
        guard !accounts.busy, !email.isEmpty, !password.isEmpty else { return }
        accounts.signIn(email: email, password: password)
    }
}
