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
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).accessibilityHidden(true)
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(MYMSStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.16)) }
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
            let wide = geometry.size.width >= 780 && !typeSize.isAccessibilitySize
            let inset: CGFloat = wide ? 32 : 16
            let width = min(wide ? 980 : 530, max(0, geometry.size.width - inset * 2))
            let formWidth = wide ? (width - 20) * 0.54 : width
            let layout = wide
                ? AnyLayout(HStackLayout(alignment: .center, spacing: 20))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))

            ScrollView {
                layout {
                    introduction(wide: wide)
                        .frame(width: wide ? width - formWidth - 20 : width)
                    VStack(alignment: .leading, spacing: 18) { content }
                        .padding(wide ? 32 : 20)
                        .frame(width: formWidth, alignment: .leading)
                        .mymsCard()
                }
                .padding(inset)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MYMSStyle.canvas.ignoresSafeArea())
        .tint(MYMSStyle.accent)
    }

    private func introduction(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: wide ? 64 : 18) {
            MYMSWordmark()

            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(wide ? 32 : 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background {
            ZStack(alignment: .topTrailing) {
                MYMSStyle.ink
                // Echo the angles of the existing MYMS mark in the corner of the panel.
                Canvas { context, size in
                    let origin = CGPoint(x: size.width - 46, y: -38)
                    for offset in [0, 18, 36] {
                        var line = Path()
                        let x = origin.x + CGFloat(offset)
                        line.move(to: CGPoint(x: x - 70, y: 0))
                        line.addLine(to: CGPoint(x: x - 14, y: origin.y + 140))
                        line.addLine(to: CGPoint(x: x + 54, y: 0))
                        context.stroke(line, with: .color(MYMSStyle.lime.opacity(0.15)), lineWidth: 1)
                    }
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}
