import SwiftUI

struct RegistrationScreen: View {
    @ObservedObject var accounts: Accounts
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var ageGroup: AgeGroup?

    private var passwordsDiffer: Bool {
        !confirmation.isEmpty && confirmation != password
    }

    var body: some View {
        AccountPage(title: "회원가입", subtitle: "계정을 만들고 운동 추천에 사용할 연령대를 선택하세요.") {
            AccountEmailField(email: $email)
            AccountField(title: "비밀번호") {
                SecureField("8자 이상", text: $password)
                    .accessibilityLabel("비밀번호")
                    .textContentType(.newPassword)
            }
            AccountField(title: "비밀번호 확인") {
                SecureField("비밀번호 다시 입력", text: $confirmation)
                    .accessibilityLabel("비밀번호 확인")
                    .textContentType(.newPassword)
            }
            AccountField(title: "연령대") {
                AgeGroupPicker(selection: $ageGroup)
                    .labelsHidden()
                    .pickerStyle(.menu)
            }
            if passwordsDiffer {
                Text("비밀번호가 일치하지 않습니다.").font(.footnote).foregroundStyle(.red)
            } else if let message = accounts.message {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
            Button {
                guard let ageGroup, password == confirmation else { return }
                accounts.register(email: email, password: password, ageGroup: ageGroup)
            } label: {
                Text("계정 만들기").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(accounts.busy || email.isEmpty || password.count < 8 || password != confirmation || ageGroup == nil)

            Text("계정과 운동 데이터는 Supabase에 저장됩니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { accounts.message = nil }
        .onDisappear { accounts.message = nil }
    }
}
