import SwiftUI

struct AccountEmailField: View {
    @Binding var email: String

    var body: some View {
        AccountField(title: "이메일") {
            TextField("name@example.com", text: $email)
                .accessibilityLabel("이메일")
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

struct AccountField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold)).accessibilityHidden(true)
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(Color(uiColor: .systemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct AccountPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 850 && !typeSize.isAccessibilitySize
            let inset: CGFloat = wide ? 32 : 20
            let contentWidth = min(wide ? 940 : 480, max(0, geometry.size.width - inset * 2))
            let panelWidth = wide ? (contentWidth - 24) / 2 : contentWidth
            let layout = wide
                ? AnyLayout(HStackLayout(alignment: .center, spacing: 24))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))

            ScrollView {
                layout {
                    introduction.frame(width: panelWidth)
                    form.frame(width: panelWidth)
                }
                .padding(inset)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .tint(Color(red: 0.05, green: 0.40, blue: 0.29))
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("MYMS", systemImage: "figure.strengthtraining.traditional")
                .font(.headline.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.23, blue: 0.19),
                         Color(red: 0.06, green: 0.40, blue: 0.29)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}
