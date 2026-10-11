import UIKit

/// 24-point paths copied from the frozen Android drawable geometry.
/// Template rendering lets the same glyph follow the application's theme tokens.
enum ParityIcon {
    case bookshelf, search, profile, source, history, download, trash, lightning, automatic, sun, moon, chapterList, detail, layoutList, layoutGrid, swap, readerStrip, readerPage, back

    func image(size: CGFloat = 24) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            context.cgContext.scaleBy(x: size / 24, y: size / 24)
            UIColor.black.setStroke()
            let path = UIBezierPath()
            path.lineWidth = self == .swap ? 2 : ([.readerStrip, .readerPage].contains(self) ? 1.6 : ([.download, .layoutList, .layoutGrid].contains(self) ? 1.8 : 1.5))
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            func line(_ points: [(CGFloat, CGFloat)], closed: Bool = false) {
                guard let first = points.first else { return }
                path.move(to: CGPoint(x: first.0, y: first.1))
                for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
                if closed { path.close() }
            }
            func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
                path.append(UIBezierPath(ovalIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)))
            }
            // Android's A commands here are circular arcs with no rotation.
            func arc(to end: CGPoint, radius: CGFloat, clockwise: Bool) {
                let start = path.currentPoint, dx = end.x - start.x, dy = end.y - start.y
                let distance = hypot(dx, dy)
                let height = sqrt(max(0, radius * radius - distance * distance / 4))
                for sign: CGFloat in [1, -1] {
                    let center = CGPoint(x: (start.x + end.x) / 2 - sign * dy * height / distance,
                                         y: (start.y + end.y) / 2 + sign * dx * height / distance)
                    let a = atan2(start.y - center.y, start.x - center.x)
                    let b = atan2(end.y - center.y, end.x - center.x)
                    var sweep = clockwise ? b - a : a - b
                    if sweep < 0 { sweep += .pi * 2 }
                    if sweep <= .pi + 0.001 {
                        path.addArc(withCenter: center, radius: radius, startAngle: a, endAngle: b, clockwise: clockwise)
                        return
                    }
                }
            }
            switch self {
            case .back:
                path.move(to: CGPoint(x: 15, y: 4)); path.addLine(to: CGPoint(x: 8, y: 12)); path.addLine(to: CGPoint(x: 15, y: 20))
            case .bookshelf:
                for x: CGFloat in [4, 8, 12, 16, 20] { line([(x, 4), (x, 20)]) }
                line([(3, 4), (21, 4)]); line([(3, 20), (21, 20)])
            case .search:
                line([(16.5, 16.5), (20, 20)]); circle(10, 10, 6)
            case .profile:
                circle(12, 8, 4)
                path.move(to: CGPoint(x: 4, y: 21))
                path.addCurve(to: CGPoint(x: 12, y: 14), controlPoint1: CGPoint(x: 4, y: 16), controlPoint2: CGPoint(x: 7, y: 14))
                path.addCurve(to: CGPoint(x: 20, y: 21), controlPoint1: CGPoint(x: 17, y: 14), controlPoint2: CGPoint(x: 20, y: 16))
            case .source:
                for x: CGFloat in [4, 14] { for y: CGFloat in [4, 14] { line([(x, y), (x + 6, y), (x + 6, y + 6), (x, y + 6)], closed: true) } }
            case .layoutList:
                for y: CGFloat in [6, 12, 18] { line([(4, y), (20, y)]) }
            case .layoutGrid:
                for x: CGFloat in [4, 14] { for y: CGFloat in [4, 14] { line([(x, y), (x + 6, y), (x + 6, y + 6), (x, y + 6)], closed: true) } }
            case .swap:
                line([(4, 8), (20, 8)]); line([(16, 4), (20, 8), (16, 12)])
                line([(20, 16), (4, 16)]); line([(8, 12), (4, 16), (8, 20)])
            case .readerStrip, .readerPage:
                path.append(UIBezierPath(roundedRect: CGRect(x: 3.4, y: 4, width: 17.2, height: 16), cornerRadius: 1.6))
                if self == .readerStrip {
                    line([(12, 8), (12, 16)]); line([(9, 13), (12, 16), (15, 13)])
                } else {
                    line([(8, 12), (16, 12)]); line([(13, 9), (16, 12), (13, 15)])
                }
            case .history:
                circle(12, 12, 9); line([(12, 7), (12, 12), (16, 14)])
            case .chapterList:
                for y: CGFloat in [6, 12, 18] { line([(8, y), (20, y)]); line([(4, y), (4.01, y)]) }
            case .detail:
                circle(12, 12, 10); line([(12, 16), (12, 11)]); line([(12, 8), (12, 7.5)])
            case .download:
                line([(12, 3), (12, 15)]); line([(7, 10), (12, 15), (17, 10)])
                line([(5, 17), (5, 21), (19, 21), (19, 17)])
            case .trash:
                line([(4, 7), (20, 7)]); line([(9, 4), (15, 4), (15, 7), (9, 7)], closed: true)
                line([(6, 7), (6, 20), (18, 20), (18, 7)])
                for x: CGFloat in [9, 12, 15] { line([(x, 10), (x, 17)]) }
            case .lightning:
                line([(13, 2), (5, 14), (11, 14), (9, 22), (17, 10), (11, 10)], closed: true)
            case .automatic:
                path.move(to: CGPoint(x: 12, y: 3)); arc(to: CGPoint(x: 12, y: 21), radius: 9, clockwise: false)
                line([(5, 5), (7, 7)]); line([(5, 19), (7, 17)]); line([(3, 12), (5, 12)])
            case .sun:
                circle(12, 12, 5)
                for points: [(CGFloat, CGFloat)] in [[(12, 2), (12, 4)], [(12, 20), (12, 22)], [(2, 12), (4, 12)], [(20, 12), (22, 12)], [(5, 5), (6.5, 6.5)], [(17.5, 17.5), (19, 19)], [(5, 19), (6.5, 17.5)], [(17.5, 6.5), (19, 5)]] { line(points) }
            case .moon:
                path.move(to: CGPoint(x: 21, y: 13))
                arc(to: CGPoint(x: 11, y: 3), radius: 9, clockwise: true)
                arc(to: CGPoint(x: 21, y: 13), radius: 7, clockwise: false); path.close()
            }
            path.stroke()
        }.withRenderingMode(.alwaysTemplate)
    }
}
