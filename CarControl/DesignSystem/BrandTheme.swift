import SwiftUI

extension Color {
    init(hex: Int, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// 深色 + 品牌绿主题（MG4 状态页）
enum BrandTheme {
    static let bgTop = Color(hex: 0x111713)
    static let bgBottom = Color(hex: 0x050806)
    static let card = Color(hex: 0x171E19)
    static let cardAlt = Color(hex: 0x1F2922)
    static let green = Color(hex: 0x3BFF8B)
    static let greenDim = Color(hex: 0x1E7A4A)
    static let greenDeep = Color(hex: 0x123322)
    static let danger = Color(hex: 0xFF5C5C)
    static let warning = Color(hex: 0xFFB020)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)

    static var background: some View {
        LinearGradient(colors: [bgTop, bgBottom],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

struct BrandCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(BrandTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func brandCard(padding: CGFloat = 16) -> some View {
        modifier(BrandCardModifier(padding: padding))
    }
}

/// 骨架屏块
struct SkeletonBlock: View {
    var height: CGFloat = 16
    var radius: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .frame(height: height)
            .opacity(pulse ? 0.45 : 0.9)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

/// 绿色进度条
struct GreenProgressBar: View {
    var progress: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [BrandTheme.greenDim, BrandTheme.green],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}
