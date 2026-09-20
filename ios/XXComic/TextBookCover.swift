import UIKit

enum TextBookCover {
    static func image(title: String, author: String = "") -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900), format: format).image { renderer in
            let context = renderer.cgContext
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(red: 36/255, green: 59/255, blue: 85/255, alpha: 1).cgColor, UIColor(red: 20/255, green: 30/255, blue: 48/255, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 900), options: [])
            UIColor.white.withAlphaComponent(0.25).setStroke()
            let border = UIBezierPath(roundedRect: CGRect(x: 28, y: 28, width: 544, height: 844), cornerRadius: 16)
            border.lineWidth = 4; border.stroke()
            UIColor(red: 108/255, green: 160/255, blue: 220/255, alpha: 0.19).setFill()
            UIBezierPath(roundedRect: CGRect(x: 50, y: 60, width: 160, height: 42), cornerRadius: 8).fill()
            ("EPUB 电子书" as NSString).draw(at: CGPoint(x: 66, y: 69), withAttributes: [.font: UIFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: UIColor(red: 138/255, green: 180/255, blue: 248/255, alpha: 1)])
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 9; paragraph.lineBreakMode = .byTruncatingTail
            ((title.isEmpty ? "未命名小说" : title) as NSString).draw(in: CGRect(x: 50, y: 220, width: 500, height: 490), withAttributes: [.font: UIFont.systemFont(ofSize: 46, weight: .bold), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
            if !author.isEmpty {
                ("作者 · " + author as NSString).draw(in: CGRect(x: 50, y: 784, width: 500, height: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 26), .foregroundColor: UIColor.white.withAlphaComponent(0.7)])
            }
        }
    }
}
