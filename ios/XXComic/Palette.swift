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
    static let accentText = color(day: 0x1169A3, night: 0xA8DAFF)
    static let placeholder = color(day: 0xE0EFFA, night: 0x2A3F52)
    static let scrim = rgba(
        day: (10, 24, 37, 145.0 / 255.0),
        night: (6, 14, 22, 176.0 / 255.0)
    )
    static let updateBlue = color(day: 0x2B98D9, night: 0x6AB8F3)
    static let noUpdateGray = color(day: 0x8599AD, night: 0x526E87)
    static let border = color(day: 0xCFE5F3, night: 0x2F465B)
    static let borderSoft = color(day: 0xE1EFFA, night: 0x25394C)
    static let green = color(day: 0x44A185, night: 0x5BBE9D)
    static let danger = color(day: 0xC23B3B, night: 0xFF7A7A)
    static let onDanger = color(day: 0xFFFFFF, night: 0x1A0A0A)

    /// Returns a readable text color against `background` using WCAG sRGB contrast >= 4.5.
    /// Mirrors `UiContrast.readable(foreground, background, fallback)`.
    static func readable(foreground: UIColor, background: UIColor, fallback: UIColor) -> UIColor {
        UIColor { traits in
            let fg = foreground.resolvedColor(with: traits)
            let bg = background.resolvedColor(with: traits)
            let fb = fallback.resolvedColor(with: traits)
            if contrastRatio(fg, bg) >= 4.5 {
                return fg
            }
            if contrastRatio(fb, bg) >= 4.5 {
                return fb
            }
            let blackRatio = contrastRatio(.black, bg)
            let whiteRatio = contrastRatio(.white, bg)
            return blackRatio > whiteRatio ? .black : .white
        }
    }

    static func contrastRatio(_ foreground: UIColor, _ background: UIColor) -> Double {
        let a = relativeLuminance(foreground)
        let b = relativeLuminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func relativeLuminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if !color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            if let srgb = CGColorSpace(name: CGColorSpace.sRGB),
               let converted = color.cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
               let comps = converted.components, comps.count >= 3 {
                r = comps[0]
                g = comps[1]
                b = comps[2]
            } else {
                var white: CGFloat = 0
                if color.getWhite(&white, alpha: &a) {
                    r = white; g = white; b = white
                }
            }
        }
        return 0.2126 * linearChannel(Double(r))
            + 0.7152 * linearChannel(Double(g))
            + 0.0722 * linearChannel(Double(b))
    }

    private static func linearChannel(_ value: Double) -> Double {
        let clamped = max(0, min(1, value))
        return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
    }

    private static func color(day: Int, night: Int) -> UIColor {
        UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? night : day
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }

    private static func rgba(
        day: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        night: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    ) -> UIColor {
        UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? night : day
            return UIColor(red: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: c.a)
        }
    }
}
