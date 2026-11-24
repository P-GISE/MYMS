import SwiftUI
import UIKit

enum MYMSStyle {
    static let ink = Color(red: 0.055, green: 0.19, blue: 0.16)
    static let lime = Color(red: 0.83, green: 0.96, blue: 0.46)

    static let accent = adaptive(
        light: UIColor(red: 0.04, green: 0.38, blue: 0.27, alpha: 1),
        dark: UIColor(red: 0.49, green: 0.86, blue: 0.68, alpha: 1)
    )
    static let onAccent = adaptive(
        light: .white,
        dark: UIColor(red: 0.055, green: 0.19, blue: 0.16, alpha: 1)
    )
    static let canvas = adaptive(
        light: UIColor(red: 0.95, green: 0.96, blue: 0.94, alpha: 1),
        dark: UIColor(red: 0.055, green: 0.08, blue: 0.075, alpha: 1)
    )
    static let surface = adaptive(
        light: .white,
        dark: UIColor(red: 0.095, green: 0.13, blue: 0.12, alpha: 1)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

extension View {
    func mymsPrimaryButton() -> some View {
        buttonStyle(.borderedProminent)
            .foregroundStyle(MYMSStyle.onAccent)
    }

    func mymsCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return background(MYMSStyle.surface, in: shape)
            .overlay { shape.strokeBorder(Color(uiColor: .separator).opacity(0.38), lineWidth: 1).allowsHitTesting(false) }
    }
}

struct MYMSWordmark: View {
    var body: some View {
        HStack(spacing: 9) {
            Canvas { context, _ in
                var mark = Path()
                mark.move(to: CGPoint(x: 3, y: 30))
                for point in [CGPoint(x: 10, y: 4), CGPoint(x: 21, y: 20),
                              CGPoint(x: 33, y: 4), CGPoint(x: 39, y: 30)] {
                    mark.addLine(to: point)
                }
                context.stroke(mark, with: .color(MYMSStyle.lime),
                               style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                context.fill(Path(ellipseIn: CGRect(x: 29, y: 0, width: 8, height: 8)), with: .color(.white))
            }
            .frame(width: 42, height: 34)
            .accessibilityHidden(true)
            Text("MYMS").font(.title2.weight(.heavy)).tracking(2)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MYMS")
    }
}
