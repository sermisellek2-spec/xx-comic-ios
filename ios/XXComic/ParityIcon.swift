import UIKit

/// 24-point paths copied from the frozen Android drawable geometry.
/// Template rendering lets the same glyph follow the application's theme tokens.
enum ParityIcon {
    case bookshelf, search, profile, source, history, download, trash, lightning, automatic, sun, moon
    case chapterList, detail, layoutList, layoutGrid, swap, readerStrip, readerPage, readerManga
    case back, chevronDown, settings, plus
    case arrowUpTop, blacklist, eyeOff, share, sliders, moreDots, cloudOff, folder, check
    case favorite, favoriteFill, refresh, chevronRight, close

    private var strokeWidth: CGFloat {
        switch self {
        case .check: return 2.8
        case .swap, .plus, .chevronDown, .arrowUpTop: return 2.0
        case .share: return 1.9
        case .download, .layoutList, .layoutGrid, .folder, .refresh: return 1.8
        case .readerStrip, .readerPage, .readerManga: return 1.6
        default: return 1.5
        }
    }

    private var isFilled: Bool {
        switch self {
        case .moreDots, .favoriteFill: return true
        default: return false
        }
    }

    func image(size: CGFloat = 24) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            context.cgContext.scaleBy(x: size / 24, y: size / 24)
            UIColor.black.setStroke()
            UIColor.black.setFill()
            let path = UIBezierPath()
            path.lineWidth = strokeWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

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
            func arc(to end: CGPoint, radius: CGFloat, clockwise: Bool, largeArc: Bool = false) {
                let start = path.currentPoint, dx = end.x - start.x, dy = end.y - start.y
                let distance = hypot(dx, dy)
                guard distance > 0 else { return }
                let height = sqrt(max(0, radius * radius - distance * distance / 4))
                for sign: CGFloat in [1, -1] {
                    let center = CGPoint(x: (start.x + end.x) / 2 - sign * dy * height / distance,
                                         y: (start.y + end.y) / 2 + sign * dx * height / distance)
                    let a = atan2(start.y - center.y, start.x - center.x)
                    let b = atan2(end.y - center.y, end.x - center.x)
                    var sweep = clockwise ? b - a : a - b
                    if sweep < 0 { sweep += .pi * 2 }
                    if largeArc ? sweep >= .pi - 0.001 : sweep <= .pi + 0.001 {
                        path.addArc(withCenter: center, radius: radius, startAngle: a, endAngle: b, clockwise: clockwise)
                        return
                    }
                }
            }

            func addHeartPath() {
                path.move(to: CGPoint(x: 12, y: 21))
                path.addCurve(to: CGPoint(x: 4, y: 9), controlPoint1: CGPoint(x: 12, y: 21), controlPoint2: CGPoint(x: 4, y: 15))
                path.addCurve(to: CGPoint(x: 9, y: 4), controlPoint1: CGPoint(x: 4, y: 6), controlPoint2: CGPoint(x: 6, y: 4))
                path.addCurve(to: CGPoint(x: 12, y: 7), controlPoint1: CGPoint(x: 10.5, y: 4), controlPoint2: CGPoint(x: 12, y: 5))
                path.addCurve(to: CGPoint(x: 15, y: 4), controlPoint1: CGPoint(x: 12, y: 5), controlPoint2: CGPoint(x: 13.5, y: 4))
                path.addCurve(to: CGPoint(x: 20, y: 9), controlPoint1: CGPoint(x: 18, y: 4), controlPoint2: CGPoint(x: 20, y: 6))
                path.addCurve(to: CGPoint(x: 12, y: 21), controlPoint1: CGPoint(x: 20, y: 15), controlPoint2: CGPoint(x: 12, y: 21))
                path.close()
            }

            switch self {
            case .back:
                path.move(to: CGPoint(x: 15, y: 4)); path.addLine(to: CGPoint(x: 8, y: 12)); path.addLine(to: CGPoint(x: 15, y: 20))
            case .chevronRight:
                line([(9, 4), (16, 12), (9, 20)])
            case .chevronDown:
                line([(6, 9), (12, 15), (18, 9)])
            case .plus:
                line([(12, 5), (12, 19)]); line([(5, 12), (19, 12)])
            case .close:
                line([(6, 6), (18, 18)]); line([(18, 6), (6, 18)])
            case .check:
                line([(5, 12.5), (9.5, 17), (19, 7.5)])
            case .arrowUpTop:
                line([(5, 5), (19, 5)]); line([(12, 9), (12, 19)]); line([(7, 14), (12, 9), (17, 14)])
            case .blacklist:
                circle(12, 12, 9); line([(5.64, 5.64), (18.36, 18.36)])
            case .eyeOff:
                path.move(to: CGPoint(x: 10.5, y: 5.1))
                path.addCurve(to: CGPoint(x: 12, y: 5), controlPoint1: CGPoint(x: 11, y: 5), controlPoint2: CGPoint(x: 11.5, y: 5))
                path.addCurve(to: CGPoint(x: 22, y: 12), controlPoint1: CGPoint(x: 16.5, y: 5), controlPoint2: CGPoint(x: 20.2, y: 7.9))
                path.addCurve(to: CGPoint(x: 19.35, y: 15.85), controlPoint1: CGPoint(x: 21.35, y: 13.45), controlPoint2: CGPoint(x: 20.45, y: 14.75))
                path.move(to: CGPoint(x: 17.3, y: 17.3))
                path.addCurve(to: CGPoint(x: 12, y: 19), controlPoint1: CGPoint(x: 15.75, y: 18.4), controlPoint2: CGPoint(x: 13.95, y: 19))
                path.addCurve(to: CGPoint(x: 2, y: 12), controlPoint1: CGPoint(x: 7.5, y: 19), controlPoint2: CGPoint(x: 3.8, y: 16.1))
                path.addCurve(to: CGPoint(x: 5.8, y: 7.15), controlPoint1: CGPoint(x: 2.85, y: 10.05), controlPoint2: CGPoint(x: 4.2, y: 8.35))
                path.move(to: CGPoint(x: 14.12, y: 14.12))
                arc(to: CGPoint(x: 9.88, y: 9.88), radius: 3, clockwise: true)
                line([(3, 3), (21, 21)])
            case .share:
                line([(14, 5), (20, 11), (14, 17)])
                path.move(to: CGPoint(x: 20, y: 11)); path.addLine(to: CGPoint(x: 11.5, y: 11))
                path.addCurve(to: CGPoint(x: 4, y: 18.5), controlPoint1: CGPoint(x: 7.36, y: 11), controlPoint2: CGPoint(x: 4, y: 14.36))
                path.addLine(to: CGPoint(x: 4, y: 19))
            case .sliders:
                line([(4, 6), (6.5, 6)]); line([(10.5, 6), (20, 6)]); circle(8.5, 6, 2)
                line([(4, 12), (13.5, 12)]); line([(17.5, 12), (20, 12)]); circle(15.5, 12, 2)
                line([(4, 18), (8.5, 18)]); line([(12.5, 18), (20, 18)]); circle(10.5, 18, 2)
            case .moreDots:
                circle(6, 12, 2); circle(12, 12, 2); circle(18, 12, 2)
            case .cloudOff:
                path.move(to: CGPoint(x: 6, y: 18))
                path.addLine(to: CGPoint(x: 16, y: 18))
                arc(to: CGPoint(x: 16, y: 10), radius: 4, clockwise: false)
                arc(to: CGPoint(x: 6, y: 12), radius: 6, clockwise: false)
                arc(to: CGPoint(x: 6, y: 18), radius: 4, clockwise: false)
                path.close()
                line([(5, 5), (19, 19)])
            case .folder:
                line([(3, 6), (10, 6), (12, 8), (21, 8), (21, 20), (3, 20)], closed: true)
            case .favorite, .favoriteFill:
                addHeartPath()
            case .refresh:
                line([(20, 3), (20, 7), (16, 7)])
                path.move(to: CGPoint(x: 20, y: 7))
                arc(to: CGPoint(x: 20, y: 16), radius: 8, clockwise: false, largeArc: true)
            case .settings:
                circle(12, 12, 3)
                path.move(to: CGPoint(x: 19.4, y: 15))
                arc(to: CGPoint(x: 19.73, y: 16.82), radius: 1.65, clockwise: false)
                path.addLine(to: CGPoint(x: 19.82, y: 16.91))
                arc(to: CGPoint(x: 17, y: 19.73), radius: 2, clockwise: true, largeArc: true)
                path.addLine(to: CGPoint(x: 16.91, y: 19.64))
                arc(to: CGPoint(x: 15.09, y: 19.31), radius: 1.65, clockwise: false)
                arc(to: CGPoint(x: 14, y: 20.86), radius: 1.65, clockwise: false)
                path.addLine(to: CGPoint(x: 14, y: 21))
                arc(to: CGPoint(x: 10, y: 21), radius: 2, clockwise: true, largeArc: true)
                path.addLine(to: CGPoint(x: 10, y: 20.86))
                arc(to: CGPoint(x: 8.91, y: 19.31), radius: 1.65, clockwise: false)
                arc(to: CGPoint(x: 7.09, y: 19.64), radius: 1.65, clockwise: false)
                path.addLine(to: CGPoint(x: 7, y: 19.73))
                arc(to: CGPoint(x: 4.18, y: 16.91), radius: 2, clockwise: true, largeArc: true)
                path.addLine(to: CGPoint(x: 4.27, y: 16.82))
                arc(to: CGPoint(x: 4.6, y: 15), radius: 1.65, clockwise: false)
                arc(to: CGPoint(x: 3.05, y: 13.91), radius: 1.65, clockwise: false)
                path.addLine(to: CGPoint(x: 3, y: 13.91))
                arc(to: CGPoint(x: 3, y: 9.91), radius: 2, clockwise: true, largeArc: true)
                path.addLine(to: CGPoint(x: 3.05, y: 9.91))
                arc(to: CGPoint(x: 4.6, y: 8.82), radius: 1.65, clockwise: false)
                arc(to: CGPoint(x: 4.27, y: 7), radius: 1.65, clockwise: false)
                path.addLine(to: CGPoint(x: 4.18, y: 6.91))
                arc(to: CGPoint(x: 7, y: 4.09), radius: 2, clockwise: true, largeArc: true)
                path.addLine(to: CGPoint(x: 7.09, y: 4.18))
                arc(to: CGPoint(x: 8.91, y: 4.51), radius: 1.65, clockwise: false)
                arc(to: CGPoint(x: 10, y: 2.96), radius: 1.65, clockwise: false)
                path.addLine(to: CGPoint(x: 10, y: 3))
                arc(to: CGPoint(x: 14, y: 3), radius: 2, clockwise: true, largeArc: true)
                path.addLine(to: CGPoint(x: 14, y: 2.96))
                arc(to: CGPoint(x: 15.09, y: 4.51), radius: 1.65, clockwise: false)
                arc(to: CGPoint(x: 16.91, y: 4.18), radius: 1.65, clockwise: false)
                path.addLine(to: CGPoint(x: 17, y: 4.09))
                arc(to: CGPoint(x: 19.82, y: 6.91), radius: 2, clockwise: true, largeArc: true)
                path.addLine(to: CGPoint(x: 19.73, y: 7))
                arc(to: CGPoint(x: 19.4, y: 8.82), radius: 1.65, clockwise: false)
                arc(to: CGPoint(x: 20.95, y: 9.91), radius: 1.65, clockwise: false)
                path.addLine(to: CGPoint(x: 21, y: 9.91))
                arc(to: CGPoint(x: 21, y: 13.91), radius: 2, clockwise: true, largeArc: true)
                path.addLine(to: CGPoint(x: 20.95, y: 13.91))
                arc(to: CGPoint(x: 19.4, y: 15), radius: 1.65, clockwise: false)
                path.close()
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
            case .readerStrip, .readerPage, .readerManga:
                path.append(UIBezierPath(roundedRect: CGRect(x: 3.4, y: 4, width: 17.2, height: 16), cornerRadius: 1.6))
                if self == .readerStrip {
                    line([(12, 8), (12, 16)]); line([(9, 13), (12, 16), (15, 13)])
                } else if self == .readerPage {
                    line([(8, 12), (16, 12)]); line([(13, 9), (16, 12), (13, 15)])
                } else {
                    line([(16, 12), (8, 12)]); line([(11, 9), (8, 12), (11, 15)])
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
            if isFilled {
                path.fill()
            } else {
                path.stroke()
            }
        }.withRenderingMode(.alwaysTemplate)
    }
}
