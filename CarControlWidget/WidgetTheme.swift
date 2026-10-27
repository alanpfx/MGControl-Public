import SwiftUI
import WidgetKit

// 扩展是独立 target，无法引用主 App 的 BrandTheme，这里维护一份对齐的色板。
extension Color {
    init(hex: Int, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

struct WidgetTheme {
    let accent: Color
    let accentDim: Color
    let foreground: Color
    let secondary: Color
    let tertiary: Color
    let card: Color
    let danger: Color
    let bgTop: Color
    let bgBottom: Color

    var background: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
    }

    static func resolve(_ scheme: ColorScheme) -> WidgetTheme {
        scheme == .dark ? .dark : .light
    }

    static let dark = WidgetTheme(
        accent: Color(hex: 0x3BFF8B),
        accentDim: Color(hex: 0x1E7A4A),
        foreground: Color.white.opacity(0.92),
        secondary: Color.white.opacity(0.55),
        tertiary: Color.white.opacity(0.35),
        card: Color(hex: 0x171E19),
        danger: Color(hex: 0xFF5C5C),
        bgTop: Color(hex: 0x111713),
        bgBottom: Color(hex: 0x050806)
    )

    static let light = WidgetTheme(
        accent: Color(hex: 0x11A85A),
        accentDim: Color(hex: 0x0C7A41),
        foreground: Color(hex: 0x111713),
        secondary: Color.black.opacity(0.55),
        tertiary: Color.black.opacity(0.35),
        card: Color.white,
        danger: Color(hex: 0xD93A3A),
        bgTop: Color(hex: 0xF6F9F7),
        bgBottom: Color(hex: 0xE6EEE9)
    )
}

/// iOS 17 起小组件背景必须走 `containerBackground`，iOS 16 退回普通背景。
struct WidgetBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let theme = WidgetTheme.resolve(scheme)
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { theme.background }
        } else {
            content.background(theme.background)
        }
    }
}

extension View {
    func widgetBackground() -> some View { modifier(WidgetBackground()) }
}
