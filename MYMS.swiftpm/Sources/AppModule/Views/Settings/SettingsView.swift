import SwiftUI

extension WorkoutHome {
    var settings: some View {
        NavigationStack {
            Form {
                Section("내 계정") {
                    LabeledContent("이메일", value: account.email)
                    AgeGroupPicker(selection: Binding(
                        get: { accounts.current?.ageGroup },
                        set: { accounts.updateAgeGroup($0) }
                    ))
                    Text(accounts.isLocalMode ? "이 기기의 로컬 모드" : "Supabase 계정").foregroundStyle(.secondary)
                }
                Section {
                    Button("로그아웃") {
                        accounts.signOut()
                    }.disabled(!coach.canSelect || store.syncing || store.localError != nil)
                    if !accounts.isLocalMode { Button("회원 탈퇴", role: .destructive) {
                        deletionPassword = ""
                        confirmDeletion = true
                    }.disabled(!coach.canSelect || store.syncing || store.syncError != nil || store.localError != nil) }
                } footer: {
                    if !coach.canSelect { Text("운동을 종료한 뒤 계정 설정을 변경할 수 있습니다.") }
                }
            }
            .navigationTitle("설정")
            .sheet(isPresented: $confirmDeletion, onDismiss: {
                deletionPassword = ""
                if accounts.current != nil { accounts.message = nil }
            }) {
                NavigationStack {
                    Form {
                        Section {
                            SecureField("비밀번호", text: $deletionPassword)
                        } header: {
                            Text("본인 확인")
                        } footer: {
                            Text("계정, 운동 계획, 기록과 포인트가 삭제됩니다.")
                        }
                        if let message = accounts.message {
                            Text(message).foregroundStyle(.red)
                        }
                        Button("계정과 운동 데이터 삭제", role: .destructive) {
                            Task {
                                if await accounts.delete(password: deletionPassword) {
                                    coach.stopConnection()
                                    confirmDeletion = false
                                }
                            }
                        }.disabled(deletionPassword.isEmpty)
                    }
                    .navigationTitle("회원 탈퇴")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("취소") { confirmDeletion = false }
                        }
                    }
                }
            }
        }
    }
}
