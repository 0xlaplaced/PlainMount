import SwiftUI
import MountCore

// Single native theme. System colors track macOS appearance and contrast preferences.
enum Theme {
    static let accent = Color.accentColor
    static let page = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let subtle = Color(nsColor: .quaternaryLabelColor)
    static let border = Color(nsColor: .separatorColor)
    static let warning = Color(nsColor: .systemOrange)
    static let success = Color(nsColor: .systemGreen)
    static let danger = Color(nsColor: .systemRed)
    static let title = Font.system(size: 38, weight: .semibold, design: .rounded)
    static let section = Font.system(size: 19, weight: .semibold)
    static let body = Font.system(size: 14)
    static let small = Font.system(size: 12)
    static let label = Font.system(size: 11, weight: .semibold)
    static let heroIcon: CGFloat = 56
    static let sidebar: CGFloat = 230
    static let minimumWidth: CGFloat = 860
    static let minimumHeight: CGFloat = 650
    static let defaultWidth: CGFloat = 1040
    static let defaultHeight: CGFloat = 740
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 40
    static let radius: CGFloat = 14
    static let hairline: CGFloat = 0.5
    static let buttonHeight: CGFloat = 28
}

struct Panel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(Theme.lg)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border, lineWidth: Theme.hairline))
    }
}
extension View { func panel() -> some View { modifier(Panel()) } }

func capacity(_ value: Int64) -> String {
    value.formatted(.byteCount(style: .decimal).locale(L10n.language.locale))
}
