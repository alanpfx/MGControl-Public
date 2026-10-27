import SwiftUI
import UIKit

enum Theme {
    static let primary = Color(red: 0.09, green: 0.20, blue: 0.38)   // 深蓝
    static let accent = Color(red: 0.16, green: 0.47, blue: 0.86)    // 亮蓝
    static let success = Color(red: 0.16, green: 0.65, blue: 0.42)
    static let warning = Color(red: 0.95, green: 0.60, blue: 0.12)
    static let danger = Color(red: 0.86, green: 0.25, blue: 0.25)

    static let cardCorner: CGFloat = 16
    static let pagePadding: CGFloat = 16
    static let cardPadding: CGFloat = 16
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.cardPadding)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}
