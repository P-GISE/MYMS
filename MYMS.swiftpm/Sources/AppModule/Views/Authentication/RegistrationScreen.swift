import SwiftUI

struct RegistrationScreen: View {
    @ObservedObject var accounts: Accounts
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var ageGroup: AgeGroup?
    private enum Input { case password, confirmation }
    @FocusState private var focused: Input?

    private var passwordsDiffer: Bool {
        !confirmation.isEmpty && confirmation != password
    }

    var body: some View {
        AccountPage(title: "회원가입", subtitle: "이메일로 가입하고, 운동 추천에 사용할 연령대를 선택하세요.") {
            AccountEmailField(email: $email)
                .submitLabel(.next)
                .onSubmit { focused = .password }
            AccountField(title: "비밀번호") {
                SecureField("8자 이상", text: $password)
                    .accessibilityLabel("비밀번호")
                    .textContentType(.newPassword)
                    .focused($focused, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focused = .confirmation }
            }
            AccountField(title: "비밀번호 확인") {
                SecureField("비밀번호 다시 입력", text: $confirmation)
                    .accessibilityLabel("비밀번호 확인")
                    .textContentType(.newPassword)
                    .focused($focused, equals: .confirmation)
                    .submitLabel(.done)
                    .onSubmit { focused = nil }
            }
            if passwordsDiffer {
                Label("비밀번호가 일치하지 않습니다.", systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.red)
            }

            AccountField(title: "연령대") {
                AgeGroupPicker(selection: $ageGroup)
                    .labelsHidden()
                    .pickerStyle(.menu)
            }
            if let message = accounts.message {
                Label(message, systemImage: "info.circle").font(.footnote)
            }
            Button {
                guard let ageGroup, password == confirmation else { return }
                accounts.register(email: email, password: password, ageGroup: ageGroup)
            } label: {
                HStack {
                    if accounts.busy { ProgressView().controlSize(.small) }
                    Text(accounts.busy ? "계정 만드는 중" : "계정 만들기")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
            }
            .mymsPrimaryButton()
            .controlSize(.large)
            .disabled(accounts.busy || email.isEmpty || password.count < 8 || password != confirmation || ageGroup == nil)

            Label("계정과 운동 데이터는 Supabase에 저장됩니다.", systemImage: "externaldrive")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { accounts.message = nil }
        .onDisappear {
            password = ""
            confirmation = ""
            accounts.message = nil
        }
    }
}
