import UIKit

enum Palette {
    static let background = color(day: 0xF1F9FE, night: 0x121B26)
    static let surface = color(day: 0xE3F3FC, night: 0x182635)
    static let card = color(day: 0xFFFFFF, night: 0x1D2D3E)
    static let cardSoft = color(day: 0xF3F9FF, night: 0x1A2939)
    static let text = color(day: 0x14283A, night: 0xE8F4FD)
    static let secondaryText = color(day: 0x4C697F, night: 0xB8CFE1)
    static let text2 = secondaryText
    static let text3 = color(day: 0x526C80, night: 0x809EB7)
    static let text4 = color(day: 0xB1C1D0, night: 0x526E87)
    static let accent = color(day: 0x2B98D9, night: 0x6AB8F3)
    static let onAccent = color(day: 0xFFFFFF, night: 0x0A1825)
    static let accentSoft = color(day: 0xE2F3FF, night: 0x253F54)
    static let updateBlue = color(day: 0x2B98D9, night: 0x6AB8F3)
    static let noUpdateGray = color(day: 0x8A9AA8, night: 0x526E87)
    static let border = color(day: 0xCFE5F3, night: 0x2F465B)
    static let borderSoft = color(day: 0xE1EFFA, night: 0x25394C)
    static let green = color(day: 0x44A185, night: 0x5BBE9D)
    static let danger = color(day: 0xC84545, night: 0xC84545)

    private static func color(day: Int, night: Int) -> UIColor {
        UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? night : day
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }
}
