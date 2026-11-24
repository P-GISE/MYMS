import SwiftUI

extension WorkoutHome {
    var settings: some View {
        NavigationStack {
            Form {
                Section {
                    profileHeader
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    AgeGroupPicker(selection: Binding(
                        get: { accounts.current?.ageGroup },
                        set: { accounts.updateAgeGroup($0) }
                    ))
                    .disabled(accounts.busy)
                    if accounts.busy && !confirmDeletion {
                        ProgressView("계정 정보 저장 중")
                    }
                    if !confirmDeletion, let message = accounts.message {
                        Label(message, systemImage: "info.circle").font(.footnote)
                    }
                } header: {
                    Text("운동 추천")
                } footer: {
                    Text("선택한 연령대를 운동 계획 추천에 사용합니다.")
                }

                Section {
                    Button { accounts.signOut() } label: {
                        Label(accounts.isLocalMode ? "로컬 모드 나가기" : "로그아웃",
                              systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(accounts.busy || !coach.canSelect || store.syncing || store.localError != nil)
                    if !accounts.isLocalMode {
                        Button(role: .destructive) {
                            deletionPassword = ""
                            accounts.message = nil
                            confirmDeletion = true
                        } label: {
                            Label("회원 탈퇴", systemImage: "person.crop.circle.badge.minus")
                        }
                        .disabled(accounts.busy || !coach.canSelect || store.syncing || store.syncError != nil || store.localError != nil)
                    }
                } header: {
                    Text("계정 관리")
                } footer: {
                    if !coach.canSelect { Text("운동을 종료한 뒤 계정을 전환할 수 있습니다.") }
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
            .background(MYMSStyle.canvas.ignoresSafeArea())
            .navigationTitle("설정")
            .sheet(isPresented: $confirmDeletion, onDismiss: {
                deletionPassword = ""
                if accounts.current != nil { accounts.message = nil }
            }) {
                deletionForm
            }
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("내 계정", systemImage: accounts.isLocalMode ? "ipad" : "person.crop.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MYMSStyle.lime)
            Text(accounts.isLocalMode ? "이 기기에 저장" : account.email)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(accounts.isLocalMode ? "로컬 모드" : "로그인한 계정")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(MYMSStyle.ink, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private var deletionForm: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("현재 비밀번호", text: $deletionPassword)
                        .textContentType(.password)
                        .disabled(accounts.busy)
                } header: {
                    Text("본인 확인")
                } footer: {
                    Text("탈퇴하면 계정과 운동 계획, 기록, 포인트가 모두 삭제됩니다.")
                }
                if let message = accounts.message {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.red)
                }
                Button(role: .destructive) {
                    Task {
                        if await accounts.delete(password: deletionPassword) {
                            coach.stopConnection()
                            confirmDeletion = false
                        }
                    }
                } label: {
                    Label(accounts.busy ? "삭제 중" : "계정과 운동 데이터 삭제", systemImage: "trash")
                }
                .disabled(deletionPassword.isEmpty || accounts.busy)
            }
            .scrollContentBackground(.hidden)
            .background(MYMSStyle.canvas.ignoresSafeArea())
            .navigationTitle("회원 탈퇴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { confirmDeletion = false }.disabled(accounts.busy)
                }
            }
            .interactiveDismissDisabled(accounts.busy)
        }
    }
}
