import UIKit

enum Palette {
    static let background = color(day: 0xF1F9FE, night: 0x121B26)
    static let card = color(day: 0xFFFFFF, night: 0x1D2D3E)
    static let text = color(day: 0x14283A, night: 0xE8F4FD)
    static let secondaryText = color(day: 0x4C697F, night: 0xB8CFE1)
    static let accent = color(day: 0x2B98D9, night: 0x6AB8F3)

    private static func color(day: Int, night: Int) -> UIColor {
        UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? night : day
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }
}
