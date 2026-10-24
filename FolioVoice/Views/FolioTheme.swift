import SwiftUI

/// A small semantic palette that stays legible in either appearance.
enum FolioTheme {
    static let canvas = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.075, green: 0.070, blue: 0.100, alpha: 1)
        : UIColor(red: 0.973, green: 0.965, blue: 0.945, alpha: 1) })
    static let card = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.125, green: 0.118, blue: 0.155, alpha: 1)
        : UIColor(red: 1, green: 0.998, blue: 0.986, alpha: 1) })
    static let ink = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.94, green: 0.92, blue: 0.97, alpha: 1)
        : UIColor(red: 0.145, green: 0.129, blue: 0.216, alpha: 1) })
    static let muted = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.67, green: 0.65, blue: 0.73, alpha: 1)
        : UIColor(red: 0.45, green: 0.43, blue: 0.49, alpha: 1) })
    static let violet = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.70, green: 0.63, blue: 0.98, alpha: 1)
        : UIColor(red: 0.459, green: 0.384, blue: 0.784, alpha: 1) })
    static let apricot = Color(red: 0.91, green: 0.57, blue: 0.38)
    static let line = ink.opacity(0.09)
}

struct FolioCard: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(FolioTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(FolioTheme.line, lineWidth: 1))
    }
}

extension View {
    func folioCard(padding: CGFloat = 20) -> some View { modifier(FolioCard(padding: padding)) }
}

struct SoundWave: View {
    var color: Color = FolioTheme.violet
    var height: CGFloat = 28
    private let levels: [CGFloat] = [0.25, 0.53, 0.86, 0.62, 1, 0.73, 0.38, 0.67, 0.32]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule().fill(color).frame(width: 3, height: height * level)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct BookArtwork: View {
    var compact = false

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.23)
                    .fill(LinearGradient(colors: [Color(red: 0.90, green: 0.87, blue: 0.97), Color(red: 0.79, green: 0.74, blue: 0.91)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .frame(width: size * 0.85, height: size * 0.85)
                    .offset(x: size * 0.30, y: -size * 0.18)
                Circle().fill(Color.white.opacity(0.18))
                    .frame(width: size * 0.55, height: size * 0.55)
                    .offset(x: -size * 0.32, y: size * 0.34)
                RoundedRectangle(cornerRadius: size * 0.055)
                    .fill(Color(red: 0.35, green: 0.26, blue: 0.57).opacity(0.18))
                    .frame(width: size * 0.48, height: size * 0.62)
                    .rotationEffect(.degrees(-10))
                    .offset(x: size * 0.045, y: size * 0.055)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: size * 0.045)
                        .fill(Color(red: 0.99, green: 0.97, blue: 0.92))
                    Rectangle().fill(Color(red: 0.40, green: 0.31, blue: 0.63))
                        .frame(width: size * 0.055)
                        .padding(.leading, size * 0.025)
                    VStack(alignment: .leading, spacing: size * 0.045) {
                        Capsule().fill(Color(red: 0.43, green: 0.34, blue: 0.64)).frame(width: size * 0.22, height: size * 0.016)
                        Capsule().fill(Color(red: 0.43, green: 0.34, blue: 0.64).opacity(0.5)).frame(width: size * 0.16, height: size * 0.016)
                        Spacer(minLength: 0)
                        SoundWave(color: Color(red: 0.43, green: 0.34, blue: 0.64), height: size * 0.16)
                            .scaleEffect(compact ? 0.7 : 1, anchor: .leading)
                    }
                    .padding(.vertical, size * 0.095)
                    .padding(.leading, size * 0.13)
                }
                .frame(width: size * 0.48, height: size * 0.62)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.045))
                .rotationEffect(.degrees(-10))
                Circle().fill(FolioTheme.apricot)
                    .frame(width: size * 0.19, height: size * 0.19)
                    .overlay(Image(systemName: "headphones").font(.system(size: size * 0.09, weight: .semibold)).foregroundStyle(Color.white))
                    .offset(x: size * 0.27, y: size * 0.24)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

struct RoundIconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .background(FolioTheme.ink.opacity(0.055), in: Circle())
                .foregroundStyle(FolioTheme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
